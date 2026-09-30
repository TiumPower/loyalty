# "Set & forget" lifecycle automations: welcome new members, birthday gifts, and
# win-back nudges. Config is stored per-workspace in settings["automations"].
# on_signup runs inline; run_birthday / run_winback run daily via Maintenance.
module Automations
  module_function

  # New member just signed up → give the configured welcome reward.
  def on_signup(member)
    ws  = member.workspace
    cfg = ws.automation(:welcome)
    return unless cfg["enabled"] && cfg["reward_id"].present?
    reward = ws.rewards.find_by(id: cfg["reward_id"])
    return unless reward
    return unless issue_reward(member, reward, source: "campaign")
    MemberNotifier.notify(member, "welcome", icon: "🎁", link: "/wallet?tab=owned", reward: reward.title)
  rescue => e
    Rails.logger.error("[Automations] on_signup: #{e.class} #{e.message}")
  end

  def run_birthday(today: Date.current)
    count = 0
    each_workspace(:birthday) do |ws, cfg|
      reward = ws.rewards.find_by(id: cfg["reward_id"])
      next unless reward
      Member.where.not(birthday: nil)
            .where("EXTRACT(MONTH FROM birthday) = ? AND EXTRACT(DAY FROM birthday) = ?", today.month, today.day)
            .find_each do |m|
        next if m.settings["birthday_year"].to_i == today.year # once per year
        # Out of stock: leave the year-guard unset so the gift can still go out
        # if the merchant restocks today, and say nothing rather than announce a
        # present that is not in their wallet.
        next unless issue_reward(m, reward, source: "birthday")
        m.update_columns(settings: m.settings.merge("birthday_year" => today.year))
        MemberNotifier.notify(m, "birthday", icon: "🎂", link: "/wallet?tab=owned", reward: reward.title)
        count += 1
      end
    end
    count
  end

  def run_winback(now: Time.current)
    count = 0
    each_workspace(:winback) do |ws, cfg|
      days   = cfg["days"].to_i
      days   = 30 if days <= 0
      reward = cfg["reward_id"].present? ? ws.rewards.find_by(id: cfg["reward_id"]) : nil
      lo = now - (days + 1).days
      hi = now - days.days
      Member.where(id: Purchase.not_voided.select(:member_id).distinct).find_each do |m|
        last = m.purchases.not_voided.maximum(:created_at)
        next unless last && last > lo && last <= hi                     # just crossed the threshold
        next if recent?(m.settings["winback_at"], 60.days, now)          # don't nag
        gifted = reward ? issue_reward(m, reward, source: "campaign") : nil
        body = cfg["message"].presence ||
               I18n.with_locale(MemberNotifier.locale_for(m)) {
                 I18n.t("customer.notices.winback_#{gifted ? 'gift' : 'plain'}", shop: ws.name)
               }
        MemberNotifier.notify(m, "winback", icon: "👋", link: "/", message: body)
        m.update_columns(settings: m.settings.merge("winback_at" => now.iso8601))
        count += 1
      end
    end
    count
  end

  # ---- helpers ----
  def each_workspace(kind)
    ActsAsTenant.without_tenant do
      Workspace.find_each do |ws|
        cfg = ws.automation(kind)
        next unless cfg["enabled"]
        ActsAsTenant.with_tenant(ws) { yield(ws, cfg) }
      end
    end
  end

  # Returns the Voucher, or nil when the reward has run out.
  #
  # This wrote the Voucher straight out, ignoring the stock the merchant set —
  # and unlike the wheel or a stamp card these run unattended, daily, in bulk,
  # so a birthday gift limited to "50 suất" was issued to everyone with a
  # birthday, forever, while redeemed_count sat at zero.
  def issue_reward(member, reward, source:)
    return nil unless reward
    return nil unless reward.claim_stock!
    Voucher.create!(workspace: member.workspace, member: member, reward: reward,
                    source: source, state: "active", points_spent: 0,
                    expires_at: (reward.valid_days || 30).days.from_now)
  end

  def recent?(iso, window, now)
    iso.present? && Time.parse(iso) > (now - window)
  rescue ArgumentError, TypeError
    false
  end
end
