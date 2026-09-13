module Customer
  class WalletController < BaseController
    before_action :require_workspace!
    before_action :require_member!

    MAX_VOUCHERS = 120 # the wallet loaded every voucher a member had ever held

    def index
      @member   = current_member
      # Show the catalog including not-yet-open / out-of-window rewards, open
      # ones first; the card + reward page gate redemption. Ended offers are
      # hidden entirely to keep the list tidy.
      state_order = { open: 0, upcoming: 1, closed: 2, out_of_stock: 3, inactive: 4 }
      @rewards  = current_workspace.rewards.redeemable.ordered.to_a
                    .reject { |r| r.redeem_state == :ended }
                    .sort_by { |r| [state_order.fetch(r.redeem_state, 9), r.position, r.id] }
      # "Đã đổi" listed every voucher the member had ever held, newest first, so
      # the ones they can actually use sat wherever they happened to fall among
      # a year of used and expired tickets — under a tab badge promising how
      # many were usable. Usable first (soonest to expire, so the urgent one is
      # on top), then the history, newest first. Capped: this loaded every row a
      # long-standing member had.
      # Everything still live is loaded whatever its age — capping by recency
      # would have hidden a long-dated voucher behind a wall of newer history,
      # which is worse than a long list. Only the finished ones are capped.
      live = @member.vouchers.active.includes(:reward).to_a
      usable, lapsed = live.partition(&:usable?)
      history = @member.vouchers.where.not(state: "active")
                       .recent.includes(:reward).limit(MAX_VOUCHERS).to_a
      @vouchers = usable.sort_by { |v| [v.expires_at ? 0 : 1, v.expires_at || v.created_at] } +
                  (lapsed + history).sort_by { |v| -v.created_at.to_i }
      @expiring = @vouchers.select { |v| v.usable? && v.expires_at && v.expires_at <= 7.days.from_now }
      # The wallet always opened on "Khả dụng", so a member holding points but
      # no vouchers yet — every new member — was greeted with "bạn chưa có ưu
      # đãi nào" and never saw what their points could buy. Land on whichever
      # tab actually has something in it.
      @default_tab = @vouchers.any?(&:usable?) ? "owned" : "rewards"
    end
  end
end
