class MissionProgress < ApplicationRecord
  acts_as_tenant(:workspace)

  APPROVAL_STATUSES = %w[pending approved rejected].freeze

  belongs_to :workspace
  belongs_to :member
  belongs_to :mission
  belongs_to :reviewer, class_name: "User", optional: true,
             foreign_key: :reviewed_by_id
  has_one_attached :photo

  validates :member_id, uniqueness: { scope: [ :mission_id, :period_key ] }

  scope :pending_review,   -> { where(approval_status: "pending") }
  scope :approved_reviews, -> { where(approval_status: "approved") }
  scope :rejected_reviews, -> { where(approval_status: "rejected") }

  def completed? = completed_at.present?
  def claimed?   = claimed_at.present?
  def pending?   = approval_status == "pending"
  def approved?  = approval_status == "approved"
  def rejected?  = approval_status == "rejected"
  def pct        = mission.goal.to_i.zero? ? 0 : [ (progress.to_f / mission.goal * 100).round, 100 ].min

  # Advance progress; award points once when the goal is reached.
  def advance!(by = 1, outlet: nil)
    return if completed?
    self.progress += by
    if progress >= mission.goal
      self.completed_at = Time.current
      save!
      claim!(outlet: outlet)
    else
      save!
    end
  end

  def claim!(outlet: nil, points: nil)
    return if claimed?
    amount = points || mission.reward_points
    PointTransaction.create!(workspace: workspace, member: member, kind: "mission",
                             amount: amount, source: mission, note: mission.title, outlet: outlet)
    update!(claimed_at: Time.current)
    member.recompute_points!
  end

  # ---- Photo-proof flow (review / social_share) --------------------------

  # Member submits a photo (screenshot) as proof → enters the pending queue.
  # Resubmitting after a rejection resets it back to pending.
  def submit_photo!(photo:, platform: nil, note: nil)
    return false unless mission.photo_proof? && !completed?
    self.photo.attach(photo) if photo
    assign_attributes(approval_status: "pending", submitted_at: Time.current,
                      platform: platform.presence, note: note.presence,
                      reviewed_at: nil, reviewed_by_id: nil)
    save!
  end

  # Approve a submission → mark complete and award points (per-platform aware).
  def approve!(reviewer: nil, ai: false)
    return if approved?
    update!(progress: mission.goal, completed_at: (completed_at || Time.current),
            approval_status: "approved", reviewed_at: Time.current,
            reviewed_by_id: reviewer&.id)
    claim!(points: mission.points_for(platform))
  end

  # Reject a submission → member may resubmit. No points, no completion.
  def reject!(reviewer: nil, reason: nil)
    merged_note = [ note.presence, reason.presence ].compact.join(" · ")
    update!(approval_status: "rejected", reviewed_at: Time.current,
            reviewed_by_id: reviewer&.id, note: merged_note.presence)
  end
end
