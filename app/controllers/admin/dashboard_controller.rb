module Admin
  class DashboardController < BaseController
    def show
      ActsAsTenant.without_tenant do
        @workspaces_count = Workspace.count
        @active_count     = Workspace.where(status: "active").count
        @trial_count      = Workspace.where(status: "trial").count
        @members_count    = Member.count
        @recent           = Workspace.order(created_at: :desc).limit(8).to_a
        # These two KPIs were hardcoded to 0 with a "Phase 1+" caption — a
        # development stub that shipped, so the operator's first screen reported
        # no points issued on a platform that had issued 83.767, and no alerts
        # while /admin/monitoring was flagging them.
        @points_issued    = PointTransaction.credits.sum(:amount)
        @alerts_count     = Workspace.where(status: %w[pending past_due]).count
      end
    end

    private

    def nav_key = :dashboard
  end
end
