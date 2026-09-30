module Customer
  class WalletController < BaseController
    before_action :require_workspace!
    before_action :require_member!

    # The wallet is the catalogue; what the member already holds lives on its
    # own screen (vouchers#index), as in the design.
    def index
      @member = current_member
      # Show the catalog including not-yet-open / out-of-window rewards, open
      # ones first; the card + reward page gate redemption. Ended offers are
      # hidden entirely to keep the list tidy.
      state_order = { open: 0, upcoming: 1, closed: 2, out_of_stock: 3, inactive: 4 }
      @rewards  = current_workspace.rewards.redeemable.ordered.to_a
                    .reject { |r| r.redeem_state == :ended }
                    .sort_by { |r| [state_order.fetch(r.redeem_state, 9), r.position, r.id] }
      @usable   = @member.vouchers.active.includes(:reward).select(&:usable?)
      @expiring = @usable.select { |v| v.expires_at && v.expires_at <= 7.days.from_now }
      # "260 to the next reward" — the cheapest thing still out of reach.
      @next_goal = @rewards.select { |r| r.redeem_open? && r.cost_points.to_i > @member.points_balance }
                           .min_by { |r| r.cost_points.to_i }
    end
  end
end
