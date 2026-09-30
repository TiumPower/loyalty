module Merchant
  # The shop's own inbox (bell menu in the topbar). Workspace-wide: what one
  # manager reads is read for everyone, which is what a shop actually wants.
  class AlertsController < BaseController
    PER_PAGE = 50

    def index
      @page   = [ params[:page].to_i, 1 ].max
      scope   = MerchantAlert.recent
      @total  = scope.count
      @alerts = scope.limit(PER_PAGE).offset((@page - 1) * PER_PAGE).to_a
      @has_more = @total > @page * PER_PAGE
      # Opening the inbox IS reading it — no separate "mark read" per row.
      MerchantAlert.unread.update_all(read_at: Time.current)
    end

    private

    def nav_key = :alerts
  end
end
