# Undo a bill that was rung up wrong (double tap, an extra zero, wrong customer).
#
# The ledger stays append-only: we never delete the original "earn" row, we post
# a mirroring negative "void" row so the customer's history shows what happened.
# The Purchase itself is flagged (not destroyed) so it drops out of every revenue
# and visit report while the audit trail survives.
#
# Gamification is rolled back on a best-effort basis (see Gamification.reverse_purchase):
# stamps and in-progress missions come back down, but a reward already issued and
# possibly already used is never clawed back.
class VoidPurchase
  Result = Struct.new(:ok, :error, :points_reversed, :shortfall, keyword_init: true)

  def initialize(purchase:, staff:, reason: nil)
    @purchase = purchase
    @staff    = staff
    @reason   = reason.to_s.strip.presence
  end

  def call
    return err(I18n.t("merchant.void.already")) if @purchase.voided?

    points  = @purchase.points_earned.to_i
    member  = @purchase.member
    already = false

    Purchase.transaction do
      locked = Member.lock.find(member.id) # serialize against a concurrent redeem
      # Lock the bill too and re-check: two staff hitting "undo" at the same moment
      # must not both post a reversal.
      bill = Purchase.lock.find(@purchase.id)
      if bill.voided_at.present?
        already = true
        raise ActiveRecord::Rollback
      end
      bill.update!(voided_at: Time.current, voided_by_id: @staff&.id, void_reason: @reason)

      # Take back only what the customer still holds. If they already spent
      # these points on a reward — which this service deliberately never claws
      # back — reversing the full amount left them on a NEGATIVE balance, and
      # every tier, redemption and expiry calculation then ran on a number that
      # cannot exist. The bill is still voided either way, so revenue is
      # corrected; the shortfall is recorded in the ledger note.
      reversible = [points, locked.points_balance.to_i].min
      reversible = 0 if reversible.negative?
      @shortfall = points - reversible

      if reversible.positive?
        note = I18n.t("merchant.void.ledger_note",
                      amount: ActiveSupport::NumberHelper.number_to_delimited(@purchase.amount),
                      reason: @reason.presence || I18n.t("merchant.void.no_reason"))
        if @shortfall.positive?
          note += " " + I18n.t("merchant.void.partial_note",
                               n: ActiveSupport::NumberHelper.number_to_delimited(@shortfall))
        end
        PointTransaction.create!(
          workspace: @purchase.workspace, member: member, kind: "void",
          amount: -reversible, source: @purchase, outlet: @purchase.outlet, staff: @staff,
          note: note
        )
      end
      @reversed = reversible

      Gamification.reverse_purchase(@purchase)
      locked.recompute_points!
    end

    return err(I18n.t("merchant.void.already")) if already

    @purchase.reload
    notify_member(member, @reversed.to_i)
    Result.new(ok: true, points_reversed: @reversed.to_i, shortfall: @shortfall.to_i)
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error("[VoidPurchase] ##{@purchase.id}: #{e.class} #{e.message}")
    err(I18n.t("merchant.void.failed"))
  end

  private

  # Points disappearing from a customer's balance without explanation is the
  # fastest way to lose their trust — always tell them, in their own inbox.
  def notify_member(member, points)
    return unless points.positive?
    title = I18n.t("customer.void_notice.title")
    body  = I18n.t("customer.void_notice.body", n: ActiveSupport::NumberHelper.number_to_delimited(points))
    member.notifications.create!(workspace: member.workspace, kind: "adjust",
                                 title: title, body: body, icon: "↩️", deep_link: "/history")
    PushJob.perform_later(member.workspace_id, [member.id], title, body, "/history") if PushSender.configured?
  rescue => e
    Rails.logger.error("[VoidPurchase] notify: #{e.class} #{e.message}")
  end

  def err(msg) = Result.new(ok: false, error: msg)
end
