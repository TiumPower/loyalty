module Merchant
  class BaseController < ApplicationController
    layout "merchant"

    before_action :authenticate_user!
    before_action :no_browser_cache
    before_action :set_current_workspace
    before_action :require_accessible_workspace
    before_action :enforce_workspace_access
    around_action :scope_tenant

    helper_method :current_workspace, :accessible_workspaces,
                  :current_membership, :current_program, :nav_key,
                  :scoped_outlet, :branch_scoped?, :feature_locked?,
                  :unread_alerts_count

    # Rewards to offer in any "pick a reward" list. Unusable ones (off, sold out,
    # ended) are left out — attaching one produces config that pays out nothing.
    # Whatever is already configured stays in the list under its own id, so
    # saving an existing row never silently detaches its reward.
    def assignable_rewards(*keep_ids)
      list = current_workspace.rewards.assignable.ordered.to_a
      ids  = keep_ids.flatten.compact.map(&:to_i).uniq - list.map(&:id)
      list + current_workspace.rewards.where(id: ids).ordered.to_a
    end

    # First reward among `ids` that cannot be handed out — but only counting ones
    # that are NOT already configured, so a stale setting can still be re-saved.
    def first_unassignable(*ids, keep: [])
      wanted = ids.flatten.compact.map(&:to_i).select(&:positive?).uniq - keep.flatten.compact.map(&:to_i)
      return nil if wanted.empty?
      current_workspace.rewards.where(id: wanted).find { |r| !r.assignable? }
    end

    def reward_unavailable_message(reward)
      t("merchant.rewards.reward_unavailable",
        title: reward.title, reason: reward.unassignable_reason)
    end

    # Badge on the topbar bell. Cheap (single indexed COUNT) and only meaningful
    # for owners/managers — counter staff have nothing to act on.
    def unread_alerts_count
      return @unread_alerts_count if defined?(@unread_alerts_count)
      @unread_alerts_count =
        (current_workspace && current_membership&.can_manage?) ? MerchantAlert.unread.count : 0
    end

    # A plan-gated feature the current workspace can't use (trials get everything).
    def feature_locked?(feature) = current_workspace && !current_workspace.plan_allows?(feature)

    # Render the "upgrade to unlock" screen (keeps the merchant layout/nav).
    def render_locked_feature(feature)
      @locked_feature = feature
      @upgrade_plan = Plan.lowest_allowing(feature) # real data → correct plan name
      render "merchant/shared/locked_feature"
    end

    # A non-owner assigned to a branch only sees that branch's data. Owners (and
    # managers with no branch) see the whole workspace.
    def scoped_outlet
      return @scoped_outlet if defined?(@scoped_outlet)
      m = current_membership
      @scoped_outlet = (m && !m.owner? && m.outlet_id.present?) ? m.outlet : nil
    end

    def branch_scoped? = scoped_outlet.present?

    # The outlet a counter transaction is attributed to. Non-manager staff with a
    # fixed branch are locked to it; owners/managers pick the active branch on the
    # scanner (stored in the session), defaulting to their own membership outlet.
    def current_outlet
      return @current_outlet if defined?(@current_outlet)
      m = current_membership
      # Staff with a fixed branch are locked to it.
      return @current_outlet = m.outlet if m && !m.can_manage? && m.outlet_id
      id = session[:active_outlet_id]
      # Owner/manager: session choice → their own branch → else the main (first) branch.
      @current_outlet = (id.present? && current_workspace.outlets.find_by(id: id)) ||
                        m&.outlet ||
                        current_workspace.outlets.order(:created_at).first
    end

    # Branches the current user may choose between on the scanner ([] = locked).
    def selectable_outlets
      return [] if current_membership && !current_membership.can_manage? && current_membership.outlet_id
      current_workspace.outlets.order(:name).to_a
    end
    helper_method :current_outlet, :selectable_outlets

    private

    def accessible_workspaces
      @accessible_workspaces ||= current_user ? current_user.workspaces.order(:created_at).to_a : []
    end

    def current_workspace = @current_workspace

    def set_current_workspace
      return unless current_user
      # The shop subdomain (or custom domain) is authoritative when the owner
      # can access that workspace — so cozycafe.loyalty.czin.net/merchant always
      # manages Cozy Cafe, regardless of any stale session selection.
      host_ws = workspace_from_host
      if host_ws && accessible_workspaces.any? { |w| w.id == host_ws.id }
        @current_workspace = host_ws
      elsif session[:workspace_id].present?
        @current_workspace = accessible_workspaces.find { |w| w.id == session[:workspace_id].to_i }
      end
      @current_workspace ||= accessible_workspaces.first
      session[:workspace_id] = @current_workspace&.id
    end

    # Signed in but no workspace to manage — their shop was deleted, or they
    # opened another shop's subdomain they don't belong to. Don't render broken
    # pages with a nil workspace (500s); sign out and send them to login.
    def require_accessible_workspace
      return if @current_workspace
      sign_out(current_user)
      redirect_to new_user_session_path,
        alert: "Tài khoản này hiện không quản lý cửa hàng nào. Vui lòng đăng nhập bằng đúng tài khoản cửa hàng."
    end

    def workspace_from_host
      sub = request.subdomains.first
      unless sub.blank? || TenantResolver::RESERVED_SUBDOMAINS.include?(sub)
        ws = Workspace.find_by(subdomain: sub)
      end
      ws || Workspace.find_by(custom_domain: request.host)
    end

    def scope_tenant
      if @current_workspace
        ActsAsTenant.with_tenant(@current_workspace) { yield }
      else
        yield
      end
    end

    # Lock the dashboard when the workspace is suspended (operator) or unpaid past
    # the grace period. An unpaid shop may still reach billing/payments to pay and
    # reactivate; a suspended one is fully locked (contact support).
    def enforce_workspace_access
      return unless @current_workspace
      @block_reason = @current_workspace.access_blocked_reason
      return unless @block_reason
      return if @block_reason == :unpaid && %w[billing payments].include?(controller_name)
      render "merchant/shared/locked", layout: "auth", status: :forbidden
    end

    def current_membership
      return nil unless current_user && current_workspace
      @current_membership ||= current_user.membership_for(current_workspace)
    end

    def current_program
      @current_program ||= current_workspace&.program
    end

    def require_manager!
      redirect_to merchant_root_path, alert: "Chỉ chủ cửa hàng/quản lý mới có quyền." unless current_membership&.can_manage?
    end

    def require_owner!
      redirect_to merchant_root_path, alert: "Chỉ chủ cửa hàng mới có quyền." unless current_membership&.owner?
    end

    # Overridden per controller to highlight the active sidebar item.
    def nav_key = nil
  end
end
