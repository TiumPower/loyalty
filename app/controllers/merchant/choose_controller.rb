module Merchant
  # Post-login shop picker for owners/staff with more than one workspace.
  # Kept outside Merchant::BaseController so it isn't tenant-scoped or locked.
  class ChooseController < ApplicationController
    layout "auth"
    before_action :authenticate_user!

    def show
      @workspaces = current_user.workspaces.order(:created_at).to_a
      # 0 or 1 shop → no choice to make.
      if @workspaces.size == 1
        return redirect_to merchant_url_for(@workspaces.first, merchant_home_path), allow_other_host: true
      end
      load_card_stats
    end

    private

    # The three numbers and the "last activity" line on each card. One grouped
    # query per fact, not one per shop: this page is the first thing a
    # multi-shop owner sees after signing in.
    def load_card_stats
      ids = @workspaces.map(&:id)
      ActsAsTenant.without_tenant do
        @members  = Member.where(workspace_id: ids).group(:workspace_id).count
        @outlets  = Outlet.where(workspace_id: ids).group(:workspace_id).count
        @staff    = Membership.where(workspace_id: ids).group(:workspace_id).count
        @last_seen = PointTransaction.where(workspace_id: ids).group(:workspace_id).maximum(:created_at)
      end
      @roles = current_user.memberships.where(workspace_id: ids).index_by(&:workspace_id)
    end
  end
end
