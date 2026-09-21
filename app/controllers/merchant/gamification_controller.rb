module Merchant
  class GamificationController < BaseController
    before_action :require_manager!, only: [:update_wheel]

    def show
      return render_locked_feature(:gamification) if feature_locked?(:gamification)
      @program     = current_program
      @stamp_cards = current_workspace.stamp_cards.ordered.to_a
      @missions    = current_workspace.missions.ordered.to_a
      @badges      = current_workspace.badges.ordered.to_a
      @wheel       = current_workspace.spin_wheel || current_workspace.build_spin_wheel
      # Everything already wired up stays pickable; nothing new that is unusable.
      @rewards     = assignable_rewards(@stamp_cards.map(&:reward_id), @badges.map(&:reward_id),
                                        @wheel.segments.to_a.map { |sg| sg["reward_id"] })
      @new_stamp_card = StampCard.new(target_count: 9)
      @new_mission    = Mission.new(period: "daily", reward_points: 20, goal: 1)
    end

    def update_wheel
      wheel = current_workspace.spin_wheel || current_workspace.build_spin_wheel
      rows = (params[:segments] || {}).values
      # A prize the customer can't actually receive must not be spun for: only
      # assignable rewards, plus whatever this wheel already points at.
      wheel_ids = wheel.segments.to_a.map { |sg| sg["reward_id"] }
      valid_reward_ids = assignable_rewards(wheel_ids).map(&:id).to_set
      segs = rows.filter_map do |r|
        label = r[:label].to_s.strip
        next if label.blank?
        value = r[:value].to_i
        rid = r[:reward_id].to_i
        seg = { "label" => label, "weight" => [r[:weight].to_i, 1].max,
                "color" => r[:color].presence || "#E08A3C" }
        if rid.positive? && valid_reward_ids.include?(rid)
          # Prize is a reward voucher (points ignored).
          seg.merge("kind" => "reward", "reward_id" => rid, "value" => 0)
        else
          seg.merge("kind" => value.positive? ? "points" : "none", "value" => value)
        end
      end
      wheel.segments    = segs
      wheel.cost_points = params[:cost_points].to_i if params[:cost_points].present?
      wheel.daily_free  = params[:daily_free] == "1"
      wheel.save!
      redirect_to merchant_gamification_path, notice: "Đã cập nhật vòng quay may mắn."
    end

    private

    def nav_key = :gamification
  end
end
