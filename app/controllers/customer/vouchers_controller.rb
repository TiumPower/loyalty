module Customer
  class VouchersController < BaseController

    before_action :require_workspace!
    before_action :require_member!
    before_action :set_voucher, except: :index

    MAX_VOUCHERS = 120 # this used to load every voucher a member had ever held

    # The vouchers a member holds, split by state — its own screen in the design.
    def index
      @member = current_member
      # Everything still live is loaded whatever its age: capping by recency
      # would hide a long-dated voucher behind a wall of newer history. Only the
      # finished ones are capped.
      live = @member.vouchers.active.includes(:reward).to_a
      usable, lapsed = live.partition(&:usable?)
      history = @member.vouchers.where.not(state: "active")
                       .recent.includes(:reward).limit(MAX_VOUCHERS).to_a
      # Usable first, soonest to expire on top, so the urgent one leads.
      @usable  = usable.sort_by { |v| [v.expires_at ? 0 : 1, v.expires_at || v.created_at] }
      @used    = history.select { |v| v.state == "used" }.sort_by { |v| -v.created_at.to_i }
      @expired = (lapsed + history.reject { |v| v.state == "used" }).sort_by { |v| -v.created_at.to_i }
      @tab = %w[available used expired].include?(params[:tab]) ? params[:tab] : default_tab
    end

    # Renders one of: used confirmation / expired / point-of-use code / detail.
    def show; end

    # Activate (or refresh) the one-time use code, then show the code screen.
    def use
      @voucher.start_use! if @voucher.usable?
      redirect_to member_voucher_path(@voucher)
    end

    # Polled by the use screen so the phone flips to "đã dùng" once the counter
    # verifies it.
    def status
      render json: {
        state: @voucher.state,
        used_at: @voucher.used_at&.strftime("%H:%M %d/%m"),
        outlet: @voucher.used_outlet&.name,
        token_seconds: @voucher.use_token_seconds_left
      }
    end

    private

    # Mở sẵn tab đầu tiên CÓ gì để xem, thay vì bắt khách tự dò.
    #
    # Khi chưa có voucher nào thì cả ba tab đều rỗng — trước đây rơi xuống tận
    # "Hết hạn", nên ví trống lại mở ở tab vô nghĩa nhất và câu đầu khách đọc là
    # "Chưa có voucher nào hết hạn". Ví trống thì mở "Khả dụng": đó là chỗ
    # voucher đầu tiên của họ sẽ xuất hiện.
    def default_tab
      return "available" if @usable.any?
      return "used"      if @used.any?
      return "expired"   if @expired.any?
      "available"
    end


    def set_voucher
      @voucher = current_member.vouchers.includes(:reward).find(params[:id])
    end
  end
end
