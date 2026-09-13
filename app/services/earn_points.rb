# Awards points for a purchase: computes base points from the program's earn
# rate, applies the member's tier multiplier, writes a Purchase + ledger entry
# atomically, and refreshes the member's cached balance/tier.
class EarnPoints
  Result = Struct.new(:purchase, :points, :multiplier, :tier_before, :tier_after,
                      :leveled_up, keyword_init: true)

    def initialize(member:, amount:, outlet: nil, staff: nil, source: "staff_scan",
                   idempotency_key: nil)
      @member = member
      @amount = amount.to_i
      @outlet = outlet
      @staff  = staff
      @source = source
      @idempotency_key = idempotency_key.presence
      @program = member.workspace.program
    end

    def call
      # Exactly-once. The counter is the worst place for a double award: a slow
      # network, an impatient second tap or a back-button resubmit used to pay
      # the customer twice, with no way to tell that from two real purchases.
      # The scanner mints a key per lookup; the unique index is what enforces it.
      if (existing = previous_award)
        return replay(existing)
      end

      base = @program.points_for(@amount)
      mult = (@program.tiers_enabled ? (@member.tier&.multiplier || 1) : 1).to_f
      points = (base * mult).floor
      tier_before = @member.tier

      purchase = nil
      Purchase.transaction do
        purchase = Purchase.create!(
          workspace: @member.workspace, member: @member, outlet: @outlet,
          staff: @staff, amount: @amount, points_earned: points, source: @source,
          idempotency_key: @idempotency_key
        )
        if points.positive?
          PointTransaction.create!(
            workspace: @member.workspace, member: @member, kind: "earn",
            amount: points, source: purchase, outlet: @outlet, staff: @staff,
            expires_at: @program.points_expire_at(purchase.created_at)
          )
        end
        @member.recompute_points!
      end

      Gamification.after_purchase(purchase)
      Referrals.on_purchase(@member)

      tier_after = @member.reload.tier
      Result.new(purchase: purchase, points: points, multiplier: mult,
                 tier_before: tier_before, tier_after: tier_after,
                 leveled_up: tier_before&.key != tier_after&.key)
    rescue ActiveRecord::RecordNotUnique
      # Two taps raced past the read above; the index settled it.
      (again = previous_award) ? replay(again) : raise
    end

    private

    def previous_award
      return nil if @idempotency_key.nil?
      Purchase.unscoped.find_by(workspace_id: @member.workspace_id,
                                idempotency_key: @idempotency_key)
    end

    # Report the award that already happened rather than making a second one,
    # so the cashier sees the same success screen instead of a confusing error.
    def replay(purchase)
      tier = @member.reload.tier
      Result.new(purchase: purchase, points: purchase.points_earned,
                 multiplier: (@program.tiers_enabled ? (tier&.multiplier || 1) : 1).to_f,
                 tier_before: tier, tier_after: tier, leveled_up: false)
    end
  end
