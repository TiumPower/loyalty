module Merchant
  class DomainsController < BaseController
    before_action :require_manager!, except: [:show]

    def show
      @workspace = current_workspace
      @default_host = "#{@workspace.subdomain}.#{ApplicationController::PLATFORM_HOST}"
      @verify_token = verify_token
      # The manifest the customer's phone actually reads when they install the
      # app, so this page shows the real values rather than a mock-up.
      @manifest = {
        "name"             => @workspace.name,
        "short_name"       => @workspace.name.to_s[0, 30],
        "description"      => @workspace.branding_value("tagline").presence || t("merchant.domain.manifest_desc_default"),
        "theme_color"      => @workspace.theme_value("primary"),
        "background_color" => @workspace.theme_value("surface"),
        "display"          => "standalone",
      }
    end

    # Custom domains are hidden for now — set up manually by ops (no automated
    # cert/host provisioning yet). Keep these endpoints inert so a stray POST
    # can't store an unusable domain.
    def update
      redirect_to merchant_domain_path, notice: t("merchant.domain.soon_note")
    end

    def verify
      redirect_to merchant_domain_path, notice: t("merchant.domain.soon_note")
    end

    private

    def nav_key = :domain

    def verify_token
      "loyalty-verify=#{Digest::SHA256.hexdigest("#{current_workspace.id}-domain")[0, 24]}"
    end
  end
end
