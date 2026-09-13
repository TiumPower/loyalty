module Admin
  class PlansController < BaseController
    def index
      Plan.seed_defaults! if Plan.count.zero?
      @plans = Plan.ordered.to_a
      load_usage
    end

    def update
      @plan = Plan.find(params[:id])
      if @plan.update(plan_params)
        redirect_to admin_plans_path, notice: "Đã cập nhật gói #{@plan.name}."
      else
        @plans = Plan.ordered.to_a
        load_usage
        render :index, status: :unprocessable_entity
      end
    end

    private

    # The page warns that a change applies to every workspace on the plan, but
    # never said how many — so an operator edited a price with no idea whether
    # that was two shops or two hundred.
    def load_usage
      ActsAsTenant.without_tenant do
        @plan_usage = Workspace.group(:plan).count
        @plan_members = Member.joins(:workspace).group("workspaces.plan").count
      end
    end

    def nav_key = :plans

    def plan_params
      p = params.require(:plan).permit(:name, :price, :max_outlets, :max_members,
                                       :allow_stamps, :allow_gamification, :allow_campaigns,
                                       :allow_custom_domain, :allow_ab_testing, :features_text)
      # blank limit fields → unlimited (nil)
      p[:max_outlets] = p[:max_outlets].presence
      p[:max_members] = p[:max_members].presence
      features = p.delete(:features_text).to_s.split("\n").map(&:strip).reject(&:blank?)
      p.to_h.merge(features: features)
    end
  end
end
