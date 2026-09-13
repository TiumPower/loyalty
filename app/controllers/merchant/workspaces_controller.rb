module Merchant
  class WorkspacesController < BaseController
    def switch
      ws = accessible_workspaces.find { |w| w.id == params[:id].to_i }
      # A shop the user has no membership in simply bounced them back to where
      # they already were, with no hint that nothing had happened.
      unless ws
        return redirect_to merchant_choose_path, alert: t("merchant.choose.no_access")
      end
      session[:workspace_id] = ws.id
      # Hop to the selected workspace's own subdomain so the dashboard stays there
      # (or the scanner launcher on a phone).
      redirect_to merchant_url_for(ws, merchant_home_path), allow_other_host: true
    end
  end
end
