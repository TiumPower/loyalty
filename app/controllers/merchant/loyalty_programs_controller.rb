module Merchant
  class LoyaltyProgramsController < BaseController
    before_action :require_manager!, only: [:update]

    def show
      @program = current_program
      @program.save! if @program.new_record?
      @tiers = current_workspace.tiers.ordered.to_a
    end

    def update
      @program = current_program
      @program.save! if @program.new_record?
      attrs = program_params
      if @program.update(attrs)
        notice = "Đã lưu cấu hình chương trình."
        # Anything the plan blocked was forced off inside program_params; saying
        # so beats a success message next to a toggle that flipped itself back.
        if @blocked_features.present?
          return redirect_to merchant_loyalty_program_path,
                             alert: t("merchant.program.plan_blocked", features: @blocked_features.to_sentence)
        end
        redirect_to merchant_loyalty_program_path, notice: notice
      else
        # The re-render needs the tier grid too, or the bottom half of the page
        # vanishes when a number is refused.
        @tiers = current_workspace.tiers.ordered.to_a
        render :show, status: :unprocessable_entity
      end
    end

    private

    def nav_key = :program

    def program_params
      attrs = params.require(:loyalty_program).permit(
        :points_enabled, :tiers_enabled, :stamps_enabled, :gamification_enabled,
        :earn_points, :earn_per_amount, :currency, :scan_mode, :tier_cycle_months,
        :points_expiry_months
      )
      # Enforce plan gates — can't enable what the plan doesn't allow. Remember
      # which ones the merchant actually asked for so #update can explain itself.
      @blocked_features = []
      { stamps: [:stamps_enabled, "merchant.program.m_stamps"],
        gamification: [:gamification_enabled, "merchant.program.m_gami"] }.each do |feature, (key, label)|
        next if current_workspace.plan_allows?(feature)
        @blocked_features << t(label) if ActiveModel::Type::Boolean.new.cast(attrs[key])
        attrs[key] = false
      end
      attrs
    end
  end
end
