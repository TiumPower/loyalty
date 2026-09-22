class ApplicationController < ActionController::Base
  include Pundit::Authorization

  layout :layout_by_resource
  before_action :set_locale
  before_action :no_cache_auth_pages
  before_action :tag_error_context
  after_action :stash_toast_cookie

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  helper_method :merchant_url_for, :customer_url_for, :workspace_host,
                :merchant_home_path, :mobile_device?

  # Turbo expects a 303 See Other after a form submission. With a plain 302,
  # Turbo re-requests the redirect target as a separate GET, which drops the
  # one-shot flash — so success/notice toasts never render. Default mutating
  # redirects to 303 so the flash survives into the rendered page.
  def redirect_to(options = {}, response_options = {})
    if response_options[:status].blank? &&
       %w[POST PUT PATCH DELETE].include?(request.request_method)
      response_options[:status] = :see_other
    end
    super
  end

  # Base platform host (no subdomain), e.g. "loyalty.tiumpower.com".
  PLATFORM_HOST = ENV.fetch("PLATFORM_HOST", "loyalty.tiumpower.com")

  private

  # Merchants work inside their own workspace subdomain. Land the owner there
  # right after sign-in so every relative link in the dashboard stays on the
  # subdomain (and off the shared main domain).
  def after_sign_in_path_for(resource)
    case resource
    when AdminUser
      admin_root_path
    when User
      # More than one shop → let the owner pick which to open.
      if resource.workspaces.count > 1
        merchant_choose_path
      else
        ws = resource.workspaces.order(:created_at).first
        # stored_location_for returns a request path already (never a full URL).
        # On a phone, land on the minimal scanner launcher (scan + shop QR), not
        # the desktop dashboard webview — every role runs the counter from mobile.
        merchant_url_for(ws, stored_location_for(:user).presence || merchant_home_path)
      end
    else
      super
    end
  end

  # Send each scope back to its OWN login after logout: a merchant lands on the
  # merchant login, super admin on the admin login. (Members log out via a
  # custom controller that redirects to the shop login.)
  def after_sign_out_path_for(resource_or_scope)
    case resource_or_scope
    when :admin_user then new_admin_user_session_path
    when :user       then new_user_session_path
    else root_path
    end
  end

  # Whether to emit absolute subdomain URLs. Only in production, where the
  # wildcard cert + shared session cookie make cross-subdomain hops seamless;
  # dev/test stay on a single host via /w/:slug and /merchant paths.
  def force_subdomain_links? = Rails.env.production?

  def workspace_host(workspace) = "#{workspace.subdomain}.#{PLATFORM_HOST}"

  # Roughly "is this a phone?" from the User-Agent. Phones run the counter as a
  # kiosk, so merchants land on the minimal scanner launcher; desktops (and
  # tablets/laptops) get the full management dashboard.
  MOBILE_UA = /Mobile|Android|iPhone|iPod|BlackBerry|IEMobile|Opera Mini/i
  def mobile_device? = request&.user_agent.to_s.match?(MOBILE_UA)

  # Where a merchant "enters" their workspace: the scanner launcher on a phone,
  # the dashboard everywhere else. Used by the post-login redirect, the shop
  # picker, and the workspace switcher so every entry point agrees.
  def merchant_home_path = mobile_device? ? merchant_scan_home_path : "/merchant"

  # URL to a workspace's merchant dashboard, preferring the workspace subdomain.
  def merchant_url_for(workspace, path = "/merchant")
    return path unless force_subdomain_links? && workspace&.subdomain.present?
    "https://#{workspace_host(workspace)}#{path}"
  end

  # URL to a workspace's customer PWA.
  def customer_url_for(workspace, path = "/")
    return "#" unless workspace
    if force_subdomain_links? && workspace.subdomain.present?
      "https://#{workspace_host(workspace)}#{path}"
    else
      "/w/#{workspace.slug}#{path == '/' ? '' : path}"
    end
  end

  def layout_by_resource
    devise_controller? ? "auth" : "application"
  end

  # Which workspace (and which side of the app) an error came from. Ids only —
  # config.send_default_pii is off, so no names, phones or request bodies leave
  # the box; this is enough to find the shop that hit the bug.
  #
  # Deliberately reads the request rather than current_workspace/current_member:
  # this runs before the callbacks that resolve those, and touching a memoised
  # member accessor that early would cache a nil and sign the customer out.
  def tag_error_context
    return unless defined?(Sentry) && Sentry.initialized?
    Sentry.set_tags(
      workspace: request.subdomain.presence || "root",
      app: self.class.name.deconstantize.presence || "public"
    )
    Sentry.set_user(id: "user-#{current_user.id}") if respond_to?(:current_user, true) && current_user
  rescue StandardError
    # Never let telemetry break a request.
    nil
  end

  def set_locale
    I18n.locale = resolve_locale
  end

  def resolve_locale
    requested = params[:locale] || session[:locale]
    return requested.to_sym if requested && I18n.available_locales.map(&:to_s).include?(requested.to_s)

    if respond_to?(:current_member) && current_member
      current_member.locale.to_sym
    elsif respond_to?(:current_user) && current_user
      current_user.display_locale.to_sym
    else
      I18n.default_locale
    end
  end

  # Never cache Devise auth pages (login/logout), so a fresh login form (with the
  # up-to-date behaviour) is always fetched — avoids stale cached forms breaking
  # login after a deploy.
  def no_cache_auth_pages
    no_browser_cache if devise_controller?
  end

  # Prevent the browser back/forward cache (and any shared cache) from restoring
  # an authenticated page after logout. Called on authed back-office pages.
  def no_browser_cache
    response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, private"
    response.headers["Pragma"] = "no-cache"
  end

  # Hand flash messages to the client as a short-lived, JS-readable cookie so the
  # toast can be built after Turbo's final render (see app/javascript/toast.js).
  def stash_toast_cookie
    data = { notice: flash[:notice], alert: flash[:alert] }.compact
    return if data.empty?
    cookies[:toast] = { value: data.to_json, path: "/", httponly: false, same_site: :lax }
  end

  def user_not_authorized
    flash[:alert] = t("errors.not_authorized", default: "Bạn không có quyền thực hiện thao tác này.")
    redirect_back fallback_location: main_app.root_path
  end
end
