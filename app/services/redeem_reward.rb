# Redeems a catalog reward with points: validates availability + balance, then
# atomically issues a Voucher, debits the ledger, decrements stock, and
# recomputes the member's cached points. (Top-level — see EarnPoints note.)
#
# Concurrency: a double-tapped button (or two devices) must never issue two
# vouchers for one balance, nor push a limited reward past its stock. Both are
# enforced INSIDE the transaction — the member row is locked and their balance
# re-read from the ledger, and stock is claimed with a conditional UPDATE whose
# affected-row count tells us whether we won the race.
class RedeemReward
  Result = Struct.new(:voucher, :error, keyword_init: true)

  def initialize(member:, reward:)
    @member = member
    @reward = reward
  end

  def call
    # Cheap pre-checks for a friendly error before we take any lock.
    return err(unavailable_message) unless @reward.available?
    return err(I18n.t("customer.redeem.not_points")) if @reward.cost_points.nil?
    return err(I18n.t("customer.redeem.not_enough")) if @member.points_balance < @reward.cost_points

    voucher = nil
    error   = nil

    Voucher.transaction do
      locked = Member.lock.find(@member.id)          # serialize this member's redemptions
      balance = locked.point_transactions.sum(:amount) # authoritative, not the cached column

      if balance < @reward.cost_points
        error = I18n.t("customer.redeem.not_enough")
        raise ActiveRecord::Rollback
      end

      # Claim one unit of stock atomically (see Reward#claim_stock!).
      unless @reward.claim_stock!
        error = I18n.t("customer.redeem.sold_out")
        raise ActiveRecord::Rollback
      end

      voucher = Voucher.create!(
        workspace: @member.workspace, member: @member, reward: @reward,
        source: "redeem", state: "active", points_spent: @reward.cost_points,
        expires_at: @reward.voucher_expiry_from
      )
      PointTransaction.create!(
        workspace: @member.workspace, member: @member, kind: "redeem",
        amount: -@reward.cost_points, source: voucher, note: @reward.title
      )
      locked.recompute_points!
    end

    return err(error) if error
    @member.reload
    MerchantAlerts.reward_out_of_stock(@reward.reload) # nudge the merchant to restock
    Result.new(voucher: voucher)
  end

  private

  def unavailable_message
    @reward.redeem_window_hint || I18n.t("customer.redeem.unavailable")
  end

  def err(msg) = Result.new(error: msg)
end
