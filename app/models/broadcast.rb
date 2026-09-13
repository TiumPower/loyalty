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
