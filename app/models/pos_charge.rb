class PosCharge < ApplicationRecord
  acts_as_tenant(:workspace)

  belongs_to :workspace
  belongs_to :outlet, optional: true
  belongs_to :staff, class_name: "User", optional: true
  belongs_to :member, optional: true
  belongs_to :purchase, optional: true

  validates :amount, numericality: { greater_than: 0 }

  before_validation :assign_token, on: :create
  before_validation :set_expiry,   on: :create

  scope :open, -> { where(state: "open") }

  def expired? = expires_at.present? && expires_at < Time.current
  def open?    = state == "open" && !expired?

  # Member self-scan earn (§6.2): awards points for the encoded amount once.
  def claim!(member)
    return [ nil, :expired ] if expired?
    return [ nil, :used ]    if state == "claimed"

    result = nil
    PosCharge.transaction do
      locked = PosCharge.lock.find(id)
      return [ nil, :used ] unless locked.state == "open"
      result = EarnPoints.new(member: member, amount: amount, outlet: outlet,
                              staff: staff, source: "pos_scan").call
      update!(state: "claimed", member: member, purchase: result.purchase,
              points_awarded: result.points, claimed_at: Time.current)
    end
    [ result, nil ]
  end

  private

  def assign_token
    return if token.present?
    loop do
      t = SecureRandom.alphanumeric(12)
      break (self.token = t) unless PosCharge.unscoped.exists?(workspace_id: workspace_id, token: t)
    end
  end

  def set_expiry
    self.expires_at ||= 30.minutes.from_now
  end
end
