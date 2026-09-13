class Broadcast < ApplicationRecord
  acts_as_tenant(:workspace)

  belongs_to :workspace
  belongs_to :created_by, class_name: "User", optional: true
  # broadcasts.campaign_id exists (with an index) and Campaign declares
  # has_many :broadcasts, but this side was never declared — so
  # CampaignsController#push, which does broadcasts.create!(campaign: …),
  # raised UnknownAttributeError on every send. A broadcast can also be
  # composed on its own, without a campaign.
  belongs_to :campaign, optional: true
  has_many :notifications, dependent: :nullify

  validates :title, presence: true
  validates :body,  presence: true

  scope :recent, -> { order(created_at: :desc) }
  # Scheduled broadcasts whose time has arrived and haven't been sent.
  scope :due, -> { where(sent_at: nil).where.not(scheduled_at: nil).where("scheduled_at <= ?", Time.current) }

  def scheduled? = scheduled_at.present? && sent_at.nil?

  # Display name for the audience — the saved filtered-group label, or the plain
  # segment label for older/unfiltered broadcasts.
  def audience_display = audience_label.presence || MemberSegments.label(segment_key)

  # Resolve the audience now and deliver (used by the scheduled-delivery job).
  # Honors the saved branch/search filters so a scheduled broadcast reaches exactly
  # the group it was composed for.
  def deliver_to_segment!
    deliver!(MemberSegments.audience(segment: segment_key, outlet_id: audience_outlet_id,
                                     q: audience_query, tier: audience_tier).to_a)
  end

  # Take ownership of a scheduled send before doing any work. Returns true only
  # for the caller that won.
  #
  # deliver! writes the notifications FIRST and sets sent_at last, so between
  # those two statements the row is still `due`. The delivery job runs every
  # five minutes; a run that overlaps the previous one — a large audience, a
  # slow push, a retry — picked the same broadcast up again and every customer
  # got the message twice. Worse, if insert_all succeeded but the final update!
  # failed, the broadcast stayed due forever and re-sent every five minutes.
  #
  # Claiming first trades a duplicate send for a possible silent miss if
  # delivery then fails. For something that lands in a customer's inbox and on
  # their phone, that is the right way round, and the job logs the failure.
  def claim_for_delivery!
    self.class.where(id: id, sent_at: nil)
        .update_all(sent_at: Time.current, updated_at: Time.current)
        .positive?
  end

  # Fan out an in-app notification to every member in the segment.
  def deliver!(members)
    now = Time.current
    rows = members.map do |m|
      { workspace_id: workspace_id, member_id: m.id, broadcast_id: id,
        title: title, body: body, kind: "promo", created_at: now, updated_at: now }
    end
    Notification.insert_all(rows) if rows.any?
    update!(sent_count: rows.size, sent_at: now)
    # Push to installed PWAs (in-app inbox is populated above regardless).
    PushJob.perform_later(workspace_id, members.map(&:id), title, body.to_s, "/notifications") if rows.any?
  end
end
