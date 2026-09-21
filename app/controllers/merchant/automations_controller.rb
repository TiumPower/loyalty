module Merchant
  class AutomationsController < BaseController
    before_action :require_manager!

    def show
      @cfg     = current_workspace.settings.fetch("automations", {})
      @rewards = assignable_rewards(@cfg.values.map { |c| c.is_a?(Hash) ? c["reward_id"] : nil })
    end

    def update
      autos = {
        "welcome"  => { "enabled" => flag("welcome", "enabled"), "reward_id" => field("welcome", "reward_id").presence },
        "birthday" => { "enabled" => flag("birthday", "enabled"), "reward_id" => field("birthday", "reward_id").presence },
        "winback"  => { "enabled" => flag("winback", "enabled"), "reward_id" => field("winback", "reward_id").presence,
                        "days" => field("winback", "days").to_i, "message" => field("winback", "message").to_s.strip.presence },
      }
      # An automation pointing at an unusable reward fires and gives nothing.
      current_ids = current_workspace.settings.fetch("automations", {}).values
                                     .map { |c| c.is_a?(Hash) ? c["reward_id"] : nil }
      if (bad = first_unassignable(autos.values.map { |c| c["reward_id"] }, keep: current_ids))
        return redirect_to merchant_automations_path, alert: reward_unavailable_message(bad)
      end
      current_workspace.update!(settings: current_workspace.settings.merge("automations" => autos))
      redirect_to merchant_automations_path, notice: "Đã lưu cấu hình tự động hoá."
    end

    private

    def nav_key = :automations
    def field(kind, key) = params.dig(:automations, kind, key)
    def flag(kind, key)  = field(kind, key) == "1"
  end
end
