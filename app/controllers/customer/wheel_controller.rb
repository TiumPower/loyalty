module Customer
  class WheelController < BaseController
    before_action :require_workspace!
    before_action :require_member!
    before_action :set_wheel

    def show
      @member = current_member
      @free   = @wheel.free_spin_available?(@member)
      # "Recent winners" — real spins across the shop, so the wheel reads as
      # something people actually win on.
      @recent = SpinLog.where(workspace: current_workspace).where.not(result_kind: "none")
                       .order(created_at: :desc).includes(:voucher).limit(5).to_a
    end

    def spin
      result = @wheel.spin!(current_member)
      if result[:error]
        render json: { error: "Bạn không đủ điểm để quay." }, status: :unprocessable_entity
      else
        render json: {
          index: result[:index],
          label: result[:segment]["label"],
          points: result[:points],
          reward: result[:reward]&.title,
          free: result[:free],
          balance: current_member.reload.points_balance,
          free_left: @wheel.free_spin_available?(current_member)
        }
      end
    end

    private

    def set_wheel
      @wheel = current_workspace.spin_wheel || current_workspace.create_spin_wheel!
    end
  end
end
