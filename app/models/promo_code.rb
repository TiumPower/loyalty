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
  # The one-per-member check used to run before the lock was taken, so a
  # double-scanned QR ran it twice on a promo nobody had claimed yet: both
  # requests issued a voucher and the unique index turned the loser into an
  # error page instead of "bạn đã nhận rồi". Everything that decides the outcome
  # now happens under the row lock, and the index is still honoured as a last
  # line so a race can never mint two vouchers.
  def claim!(member)
    return [nil, :unavailable] unless available?

    voucher = nil
    error   = nil
    PromoCode.transaction do
      locked   = PromoCode.lock.find(id)
      existing = locked.promo_claims.find_by(member_id: member.id)
      if existing
        voucher, error = existing.voucher, :already
        raise ActiveRecord::Rollback
      end
      if locked.out_of_claims?
        error = :unavailable
        raise ActiveRecord::Rollback
      end
      # The campaign's own max_claims is not the only limit — the reward itself
      # may be capped, and that cap was being ignored here.
      unless reward.claim_stock!
        error = :unavailable
        raise ActiveRecord::Rollback
      end
      voucher = Voucher.create!(
        workspace: workspace, member: member, reward: reward,
        source: "claim_qr", state: "active", points_spent: 0,
        expires_at: reward.valid_days.days.from_now
      )
      PromoClaim.create!(workspace: workspace, promo_code: self, member: member, voucher: voucher)
      PromoCode.where(id: id).update_all("claims_count = claims_count + 1")
    end
    [voucher, error]
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    claimed = promo_claims.find_by(member_id: member.id)
    claimed ? [claimed.voucher, :already] : [nil, :unavailable]
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
