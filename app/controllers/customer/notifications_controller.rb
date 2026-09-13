module Customer
  class NotificationsController < BaseController
    before_action :require_workspace!
    before_action :require_member!

    PER = 50

    def index
      @page = [params[:page].to_i, 1].max
      scope = current_member.notifications.recent
      @notifications = scope.limit(PER).offset((@page - 1) * PER).to_a
      @has_more = scope.count > @page * PER
      # Opening the inbox marks what it shows as read — it used to mark every
      # unread row, including the ones past the page limit, so a notification
      # could be marked read without ever having been on screen.
      unread = @notifications.reject(&:read?).map(&:id)
      Notification.where(id: unread).update_all(read_at: Time.current) if unread.any?
    end

    def read_all
      current_member.notifications.unread.update_all(read_at: Time.current)
      redirect_to member_notifications_path
    end
  end
end
