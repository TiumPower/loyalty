# Periodic housekeeping run daily by MaintenanceJob (sidekiq-cron):
#   - expire vouchers past their validity window
#   - recompute cached points/tier for every member (handles cycle roll-off)
# Cross-tenant — always runs without a tenant scope.
module Maintenance
  module_function

  GRACE_DAYS = 10

  def run_all
    { vouchers_expired: expire_vouchers, points_expired: ExpirePoints.run,
      birthday_rewards: Automations.run_birthday, winback: Automations.run_winback,
      members_recomputed: recompute_members, subscriptions: sync_subscriptions,
      notifications_pruned: prune_notifications }
  end

  # Every broadcast writes one notification row per member and nothing ever
  # removed them, so a shop with a few thousand members writes six figures of
  # rows a year — all of it scanned by the unread badge on every home screen.
  # Deliberately conservative: only rows the customer has actually read, and
  # only once they are well past the point of being useful. Anything unread is
  # kept however old it is, because it is still owed to the customer.
  NOTIFICATION_TTL = 180.days

  def prune_notifications
    n = ActsAsTenant.without_tenant do
      Notification.where.not(read_at: nil)
                  .where("read_at < ?", NOTIFICATION_TTL.ago)
                  .delete_all
    end
    Rails.logger.info("[Maintenance] pruned #{n} read notifications older than #{NOTIFICATION_TTL.inspect}")
    n
  end

  # Billing lifecycle: an active workspace whose subscription lapsed moves to
  # past_due (for Super Admin visibility). The hard lock-out after GRACE_DAYS is
  # enforced dynamically at request time (Workspace#access_blocked_reason), so an
  # unpaid shop can always pay to reactivate — we never auto-flip it to
  # "suspended" (that status is reserved for a manual operator suspension).
  # Paid/pending/trial workspaces are left alone.
  def sync_subscriptions
    moved = { past_due: 0 }
    ActsAsTenant.without_tenant do
      Workspace.where(status: "active").where.not(paid_until: nil).find_each do |ws|
        days_over = (Date.current - ws.paid_until.to_date).to_i
        next if days_over <= 0
        ws.update_columns(status: "past_due"); moved[:past_due] += 1
      end
    end
    Rails.logger.info("[Maintenance] subscriptions #{moved.inspect}")
    moved
  end

  def expire_vouchers
    n = ActsAsTenant.without_tenant do
      Voucher.where(state: "active")
             .where("expires_at IS NOT NULL AND expires_at < ?", Time.current)
             .update_all(state: "expired", updated_at: Time.current)
    end
    Rails.logger.info("[Maintenance] expired #{n} vouchers")
    n
  end

  def recompute_members
    count = 0
    ActsAsTenant.without_tenant do
      Member.includes(:workspace).find_each do |member|
        ActsAsTenant.with_tenant(member.workspace) { member.recompute_points! }
        count += 1
      end
    end
    Rails.logger.info("[Maintenance] recomputed #{count} members")
    count
  end
end
