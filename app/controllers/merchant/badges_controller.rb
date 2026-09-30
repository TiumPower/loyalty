module Merchant
  class BadgesController < BaseController
    before_action :require_manager!

    def create
      badge = current_workspace.badges.new(badge_params)
      badge.key = unique_key(badge.name)
      if badge.save
        redirect_to merchant_gamification_path, notice: "Đã thêm huy hiệu “#{badge.name}”."
      else
        redirect_to merchant_gamification_path, alert: badge.errors.full_messages.to_sentence
      end
    end

    def update
      badge = current_workspace.badges.find(params[:id])
      if badge.update(badge_params)
        redirect_to merchant_gamification_path, notice: "Đã cập nhật huy hiệu “#{badge.name}”."
      else
        redirect_to merchant_gamification_path, alert: badge.errors.full_messages.to_sentence
      end
    end

    def destroy
      current_workspace.badges.find(params[:id]).destroy
      redirect_to merchant_gamification_path, notice: "Đã xoá huy hiệu."
    end

    private

    def nav_key = :games

    def badge_params
      params.require(:badge).permit(:name, :description, :icon, :criteria_type, :threshold, :reward_points, :reward_id)
    end

    # Badge keys are unique per workspace; derive a stable one from the name.
    def unique_key(name)
      base = name.to_s.parameterize.presence || "badge"
      key = base
      n = 1
      key = "#{base}-#{n += 1}" while current_workspace.badges.exists?(key: key)
      key
    end
  end
end
