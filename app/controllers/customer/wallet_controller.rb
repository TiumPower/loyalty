module Customer
  class WalletController < BaseController
    before_action :require_workspace!
    before_action :require_member!

    def index
      @member   = current_member
      # Show the catalog including not-yet-open / out-of-window rewards, open
      # ones first; the card + reward page gate redemption. Ended offers are
      # hidden entirely to keep the list tidy.
      state_order = { open: 0, upcoming: 1, closed: 2, out_of_stock: 3, inactive: 4 }
      @rewards  = current_workspace.rewards.redeemable.ordered.to_a
                    .reject { |r| r.redeem_state == :ended }
                    .sort_by { |r| [state_order.fetch(r.redeem_state, 9), r.position, r.id] }
      @vouchers = @member.vouchers.recent.includes(:reward).to_a
      @expiring = @vouchers.select { |v| v.usable? && v.expires_at && v.expires_at <= 7.days.from_now }
      # The wallet always opened on "Khả dụng", so a member holding points but
      # no vouchers yet — every new member — was greeted with "bạn chưa có ưu
      # đãi nào" and never saw what their points could buy. Land on whichever
      # tab actually has something in it.
      @default_tab = @vouchers.any?(&:usable?) ? "owned" : "rewards"
    end
  end
end
