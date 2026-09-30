# Expires lapsed points (FIFO) for workspaces that configured an expiry window,
# and reminds members whose points expire within 7 days. Run daily by Maintenance.
module ExpirePoints
  module_function

  REMIND_WITHIN = 7.days

  def run
    expired_total = 0
    reminded = 0
    ActsAsTenant.without_tenant do
      Workspace.find_each do |ws|
        next unless ws.program&.points_expire?
        ActsAsTenant.with_tenant(ws) do
          Member.where("points_balance > 0").find_each do |m|
            expired_total += expire_member(m)
            reminded += remind_member(m)
          end
        end
      end
    end
    Rails.logger.info("[ExpirePoints] expired=#{expired_total} reminded=#{reminded}")
    { expired: expired_total, reminded: reminded }
  end

  def expire_member(member)
    amount = member.expirable_points
    return 0 if amount <= 0
    member.point_transactions.create!(workspace: member.workspace, kind: "expire",
                                      amount: -amount, note: "Điểm hết hạn")
    member.recompute_points!
    amount
  end

  # In-app reminder when points expire soon (at most one per member / 6 days).
  def remind_member(member)
    amt, date = member.points_expiring_soon(within: REMIND_WITHIN)
    return 0 if amt <= 0
    return 0 if member.notifications.where(kind: "reminder").where("created_at > ?", 6.days.ago).exists?
    MemberNotifier.notify(member, "points_expiring", kind: "reminder", icon: "⏳",
                          link: "/wallet?tab=rewards", n: amt,
                          date: I18n.l(date.to_date, format: :short))
    1
  rescue => e
    Rails.logger.error("[ExpirePoints] remind: #{e.class} #{e.message}")
    0
  end
end
