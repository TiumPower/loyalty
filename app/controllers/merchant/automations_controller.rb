module Merchant
  class AutomationsController < BaseController
    before_action :require_manager!

    # The three lifecycle automations the app actually runs (see Automations).
    # This is not a rule builder: each one is wired to a specific place in the
    # code, so the set is fixed and the merchant edits one at a time.
    KINDS = %w[welcome birthday winback].freeze

    def show
      load_config
    end

    def edit
      @kind = KINDS.include?(params[:kind].to_s) ? params[:kind].to_s : KINDS.first
      load_config
      @preview_body = preview_body(@kind, @cfg[@kind] || {})
    end

    def update
      # One automation at a time from its own editor; the whole set when an older
      # form (or a test) posts every key at once.
      kinds = KINDS.include?(params[:kind].to_s) ? [params[:kind].to_s] : KINDS
      autos = current_workspace.settings.fetch("automations", {}).dup
      kinds.each { |kind| autos[kind] = config_from_params(kind) }

      # An automation pointing at an unusable reward fires and gives nothing.
      current_ids = current_workspace.settings.fetch("automations", {}).values
                                     .map { |c| c.is_a?(Hash) ? c["reward_id"] : nil }
      if (bad = first_unassignable(autos.values.map { |c| c.is_a?(Hash) ? c["reward_id"] : nil }, keep: current_ids))
        return redirect_to merchant_automations_path, alert: reward_unavailable_message(bad)
      end
      current_workspace.update!(settings: current_workspace.settings.merge("automations" => autos))
      redirect_to merchant_automations_path, notice: t("merchant.automations.saved")
    end

    # Bật/tắt từ chính danh sách.
    #
    # `update` dựng lại toàn bộ cấu hình từ form, nên gọi nó cho một cú bật là
    # xoá sạch quà, số ngày và lời nhắn đã đặt. Ở đây chỉ chạm đúng cờ `enabled`.
    #
    # Chào mừng và Sinh nhật mà chưa chọn quà thì CHẠY CŨNG KHÔNG CHO GÌ (xem
    # Automations#on_signup / run_birthday: cả hai thoát ngay khi thiếu
    # reward_id). Bật trong trạng thái đó là dựng một cái bẫy im lặng, nên chặn
    # lại và nói rõ còn thiếu gì. Kéo khách quay lại thì chạy được không cần quà
    # — nó vẫn gửi lời nhắc.
    NEEDS_REWARD = %w[welcome birthday].freeze

    def toggle
      kind = params[:kind].to_s
      return redirect_to merchant_automations_path unless KINDS.include?(kind)

      autos = current_workspace.settings.fetch("automations", {}).dup
      cfg   = (autos[kind] || {}).dup
      turning_on = !cfg["enabled"]

      if turning_on && NEEDS_REWARD.include?(kind) && cfg["reward_id"].blank?
        return redirect_to merchant_edit_automation_path(kind), alert: t("merchant.automations.need_gift_first")
      end

      autos[kind] = cfg.merge("enabled" => turning_on)
      current_workspace.update!(settings: current_workspace.settings.merge("automations" => autos))
      redirect_to merchant_automations_path,
                  notice: t(turning_on ? "merchant.automations.turned_on" : "merchant.automations.turned_off",
                            name: t("merchant.automations.#{kind}_title"))
    end

    private

    def nav_key = :messages

    def load_config
      @cfg     = current_workspace.settings.fetch("automations", {})
      @rewards = assignable_rewards(@cfg.values.map { |c| c.is_a?(Hash) ? c["reward_id"] : nil })
    end

    def config_from_params(kind)
      cfg = { "enabled" => flag(kind, "enabled"), "reward_id" => field(kind, "reward_id").presence }
      return cfg unless kind == "winback"
      cfg.merge("days" => field("winback", "days").to_i,
                "message" => field("winback", "message").to_s.strip.presence)
    end

    # What the customer's notification will actually say, so the preview is the
    # real copy from Automations rather than an invented sample.
    def preview_body(kind, cfg)
      reward = @rewards.find { |r| r.id == cfg["reward_id"].to_i }
      case kind
      when "welcome"  then t("merchant.automations.pv_welcome_body", reward: reward&.title || t("merchant.automations.pv_reward_ph"))
      when "birthday" then t("merchant.automations.pv_birthday_body", reward: reward&.title || t("merchant.automations.pv_reward_ph"))
      else cfg["message"].presence || t("merchant.automations.pv_winback_body", shop: current_workspace.name)
      end
    end

    def field(kind, key) = params.dig(:automations, kind, key)
    def flag(kind, key)  = field(kind, key) == "1"
  end
end
