module Customer
  class BaseController < ApplicationController
    include TenantResolver

    layout "member"

    before_action :set_current_workspace
    before_action :canonical_customer_host
    before_action :enforce_workspace_access
    before_action -> { no_browser_cache if member_signed_in? }
    around_action :scope_tenant
    helper_method :current_workspace, :current_program, :current_member, :member_signed_in?

    private

    # ---- Per-shop member auth ---------------------------------------------
    # Each workspace keeps its own signed cookie (mbr_<workspace_id>), so a
    # customer of several shops stays logged in to each one independently — no
    # re-login when switching shops (a single shared Devise session couldn't do
    # this). The cookie key is per-workspace, so shops never collide even on a
    # shared host (dev) or a domain-wide cookie (prod).
    MEMBER_COOKIE_TTL = 1.year

    def current_member
      return @current_member if defined?(@current_member)
      mid = current_workspace && cookies.signed["mbr_#{current_workspace.id}"]
      @current_member = mid ? Member.where(workspace_id: current_workspace.id).find_by(id: mid) : nil
    end

    def member_signed_in? = current_member.present?

    def sign_in_member(member)
      cookies.signed["mbr_#{member.workspace_id}"] = {
        value: member.id, expires: MEMBER_COOKIE_TTL.from_now,
        httponly: true, secure: Rails.env.production?, same_site: :lax
      }
      @current_member = member
    end

    def sign_out_member
      cookies.delete("mbr_#{current_workspace.id}") if current_workspace
      @current_member = nil
    end

    def set_current_workspace
      @current_workspace = resolve_workspace
    end

    # In production, keep the customer app on the shop's own subdomain so camera
    # permission + PWA/localStorage state aren't split between the main-domain
    # path form (loyalty.tiumpower.com/w/:slug) and the subdomain. Redirects the
    # former to the latter; leaves custom domains and dev untouched.
    def canonical_customer_host
      return unless Rails.env.production? && request.get?
      ws = @current_workspace
      return if ws&.subdomain.blank?
      return if ws.custom_domain.present? && request.host == ws.custom_domain
      target = "#{ws.subdomain}.#{PLATFORM_HOST}"
      return if request.host == target
      # Only act on our own platform hosts, never on a domain we don't control.
      return unless request.host == PLATFORM_HOST || request.host.end_with?(".#{PLATFORM_HOST}")
      path = request.fullpath.sub(%r{\A/w/[^/]+}, "").presence || "/"
      redirect_to "https://#{target}#{path}", allow_other_host: true
    end

    def scope_tenant
      if @current_workspace
        ActsAsTenant.with_tenant(@current_workspace) { yield }
      else
        yield
      end
    end

    # A suspended / long-unpaid shop's customer app is turned off too.
    def enforce_workspace_access
      return unless @current_workspace&.access_blocked?
      render "customer/shared/unavailable", layout: "member", status: :forbidden
    end

    def current_workspace = @current_workspace

    def current_program
      @current_program ||= current_workspace&.program
    end

    # Non-home controllers need a resolved shop.
    def require_workspace!
      redirect_to root_path, alert: "Vui lòng chọn cửa hàng." unless current_workspace
    end

    def require_member!
      return if member_signed_in? && current_member&.workspace_id == current_workspace&.id
      # Remember where they were headed (e.g. a scanned promo QR) so we can
      # resume it right after login — otherwise a first-time scan is lost.
      session[:return_to] = request.fullpath if request.get?
      redirect_to member_login_path
    end

    # Keep /w/:slug in generated URLs only when we arrived via the path fallback.
    def default_url_options
      params[:workspace_slug].present? ? { workspace_slug: params[:workspace_slug] } : {}
    end
  end
end
