class PromoCode < ApplicationRecord
  acts_as_tenant(:workspace)

  belongs_to :workspace
  belongs_to :campaign, optional: true
  belongs_to :reward
  has_many :promo_claims, dependent: :destroy
  has_many :vouchers, through: :promo_claims

  validates :token, presence: true, uniqueness: { scope: :workspace_id }

  before_validation :assign_token, on: :create

  scope :active, -> { where(active: true) }

  def within_window?
    now = Time.current
    (starts_at.nil? || starts_at <= now) && (ends_at.nil? || ends_at >= now)
  end

  def out_of_claims? = max_claims.present? && claims_count >= max_claims
  def available?     = active? && within_window? && !out_of_claims?

  def remaining
    max_claims.nil? ? nil : [max_claims - claims_count, 0].max
  end

  def used_count  = vouchers.where(state: "used").count
  def claim_rate  = scan_count.zero? ? 0 : (claims_count.to_f / scan_count * 100).round
  def use_rate    = claims_count.zero? ? 0 : (used_count.to_f / claims_count * 100).round

  # Claim into a member's wallet (§6.6): issues a Voucher without spending points,
  # enforcing one-per-member and the total cap. Returns [voucher, error].
  def claim!(member)
    return [nil, :unavailable] unless available?
    existing = promo_claims.find_by(member_id: member.id)
    return [existing.voucher, :already] if existing

    voucher = nil
    PromoCode.transaction do
      locked = PromoCode.lock.find(id)
      return [nil, :unavailable] if locked.out_of_claims?
      # The campaign's own max_claims is not the only limit — the reward itself
      # may be capped, and that cap was being ignored here.
      return [nil, :unavailable] unless reward.claim_stock!
      voucher = Voucher.create!(
        workspace: workspace, member: member, reward: reward,
        source: "claim_qr", state: "active", points_spent: 0,
        expires_at: reward.valid_days.days.from_now
      )
      PromoClaim.create!(workspace: workspace, promo_code: self, member: member, voucher: voucher)
      PromoCode.where(id: id).update_all("claims_count = claims_count + 1")
    end
    [voucher, nil]
  end

  def register_scan! = PromoCode.where(id: id).update_all("scan_count = scan_count + 1")

  private

  def assign_token
    return if token.present?
    loop do
      t = "P#{SecureRandom.alphanumeric(9).upcase}"
      break (self.token = t) unless PromoCode.unscoped.exists?(workspace_id: workspace_id, token: t)
    end
  end
end
