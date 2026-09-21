module Merchant
  class RewardsController < BaseController
    LOW_STOCK = 5 # remaining units at or below this are flagged on the card

    before_action :require_manager!, except: [:index]
    before_action :set_reward, only: [:edit, :update, :destroy, :toggle]

    def index
      scope = current_workspace.rewards.listed
      @q = params[:q].to_s.strip
      if @q.present?
        scope = scope.where("title ILIKE :q OR description ILIKE :q", q: "%#{@q}%")
      end
      @kind = params[:kind].to_s.presence_in(Reward::KINDS)
      scope = scope.where(kind: @kind) if @kind
      @status = params[:status].to_s
      case @status
      when "active"   then scope = scope.where(active: true)
      when "inactive" then scope = scope.where(active: false)
      end
      @rewards = scope.ordered.to_a
      # The cards showed issued/used counts with two queries each, so the list
      # cost two per reward on top of the page. One grouped count covers both.
      ids = @rewards.map(&:id)
      issued = Voucher.where(reward_id: ids).group(:reward_id).count
      used   = Voucher.where(reward_id: ids, state: "used").group(:reward_id).count
      @voucher_counts = ids.index_with { |id| { issued: issued[id].to_i, used: used[id].to_i } }
    end

    def new
      @reward = Reward.new(kind: "voucher", value_unit: "vnd", valid_days: 30, active: true)
    end

    def create
      @reward = current_workspace.rewards.new(reward_params)
      if @reward.save
        redirect_to merchant_rewards_path, notice: "Đã thêm ưu đãi “#{@reward.title}”."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @reward.update(reward_params)
        # Restocking is the fix for a stamp card being held full — pay those out
        # now instead of making the customer buy one more item to trigger it.
        settle_held_stamp_cards
        redirect_to merchant_rewards_path, notice: "Đã cập nhật ưu đãi."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # Quick enable/disable issuing (without editing or deleting). The return
    # value used to be dropped, so a row that failed validation still reported
    # "Đã bật ưu đãi." while staying exactly as it was.
    def toggle
      unless @reward.update(active: !@reward.active)
        return redirect_to merchant_rewards_path(request.query_parameters),
                           alert: @reward.errors.full_messages.to_sentence.presence ||
                                  t("merchant.rewards.toggle_failed")
      end
      settle_held_stamp_cards
      redirect_to merchant_rewards_path(request.query_parameters),
                  notice: @reward.active? ? "Đã bật ưu đãi." : "Đã tắt ưu đãi."
    end

    def destroy
      if @reward.stamp_cards.exists? || @reward.campaigns.exists? || @reward.promo_codes.exists?
        # Deleting would break a stamp card / campaign — make the merchant detach first.
        redirect_to merchant_rewards_path,
          alert: "Ưu đãi đang gắn với thẻ tem hoặc chiến dịch. Hãy gỡ/xoá chúng trước khi xoá ưu đãi."
      elsif @reward.vouchers.exists?
        # Voucher đã phát cho khách → không xoá cứng được (mất lịch sử/ví khách).
        # Lưu trữ: ẩn khỏi danh sách + ngừng phát hành, giữ nguyên voucher cũ.
        unless @reward.update(active: false, archived_at: Time.current)
          return redirect_to merchant_rewards_path,
                             alert: @reward.errors.full_messages.to_sentence.presence ||
                                    t("merchant.rewards.archive_failed")
        end
        redirect_to merchant_rewards_path,
          notice: "Đã lưu trữ ưu đãi (còn voucher đã phát nên giữ lịch sử; đã ẩn khỏi danh sách và ngừng phát hành)."
      else
        @reward.destroy
        redirect_to merchant_rewards_path, notice: "Đã xoá ưu đãi."
      end
    end

    private

    def nav_key = :rewards

    def settle_held_stamp_cards
      return unless @reward.active? && @reward.in_stock? && @reward.stamp_cards.exists?
      SettleHeldStampCardsJob.perform_later(@reward.id)
    end

    def set_reward
      @reward = current_workspace.rewards.find(params[:id])
    end

    def reward_params
      p = params.require(:reward).permit(:title, :description, :kind, :icon, :cost_points,
                                         :value, :value_unit, :terms, :stock, :valid_days, :active,
                                         :starts_at, :ends_at, :expires_at)
      p[:schedule] = build_schedule
      # Voucher validity mode: "relative" (N days after claim) clears any fixed
      # expiry so the two never conflict; "fixed" uses expires_at.
      p[:expires_at] = nil if params.dig(:reward, :expiry_mode) == "relative"
      p
    end

    # Recurring availability from the multi-window form. Rails parses
    # reward[schedule][windows][<idx>][...] as a Hash keyed by the (dynamic,
    # timestamp-based) index — so iterate its .values, not as an Array.
    # Each window: days[] (wday 0-6) + optional from_hour/to_hour.
    def build_schedule
      windows_param = params.dig(:reward, :schedule, :windows)
      return {} if windows_param.blank?
      windows = windows_param.values.filter_map do |w|
        days = Array(w[:days]).map(&:to_i).select { |d| (0..6).cover?(d) }.uniq.sort
        fh = w[:from_hour].presence && w[:from_hour].to_i
        th = w[:to_hour].presence && w[:to_hour].to_i
        win = {}
        win["days"] = days if days.present?
        win["from_hour"], win["to_hour"] = fh, th if fh && th
        win.presence
      end
      { "windows" => windows }
    end
  end
end
