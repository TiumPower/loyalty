# "Set & forget" lifecycle automations: welcome new members, birthday gifts, and
# win-back nudges. Config is stored per-workspace in settings["automations"].
# on_signup runs inline; run_birthday / run_winback run daily via Maintenance.
module Automations
  module_function

  # Khách vừa đăng ký → lời chào, kèm quà nếu quán có đặt quà.
  #
  # Quà là TUỲ CHỌN. Trước đây thiếu quà là cả tự động hoá im lặng không chạy —
  # nhưng một lời chào mừng không quà vẫn là một lời chào mừng, và với quán
  # chưa kịp dựng ưu đãi thì đó là tất cả những gì họ cần.
  def on_signup(member)
    ws  = member.workspace
    cfg = ws.automation(:welcome)
    return unless cfg["enabled"]
    reward = cfg["reward_id"].present? ? ws.rewards.find_by(id: cfg["reward_id"]) : nil
    # Đã chọn quà nhưng ưu đãi đó không còn dùng được: im lặng còn hơn gửi một
    # lời chào hụt mất món quà đã hứa.
    return if cfg["reward_id"].present? && reward.nil?
    gifted = reward ? issue_reward(member, reward, source: "campaign") : nil
    return if reward && !gifted
    if gifted
      MemberNotifier.notify(member, "welcome", icon: "🎁", link: "/wallet?tab=owned", reward: reward.title)
    else
      MemberNotifier.notify(member, "welcome_plain", icon: "👋", link: "/", shop: ws.name)
    end
  rescue => e
    Rails.logger.error("[Automations] on_signup: #{e.class} #{e.message}")
  end

  def run_birthday(today: Date.current)
    count = 0
    each_workspace(:birthday) do |ws, cfg|
      # Quà là tuỳ chọn: một lời chúc sinh nhật không quà vẫn đáng gửi.
      reward = cfg["reward_id"].present? ? ws.rewards.find_by(id: cfg["reward_id"]) : nil
      next if cfg["reward_id"].present? && reward.nil?
      Member.where.not(birthday: nil)
            .where("EXTRACT(MONTH FROM birthday) = ? AND EXTRACT(DAY FROM birthday) = ?", today.month, today.day)
            .find_each do |m|
        next if m.settings["birthday_year"].to_i == today.year # once per year
        gifted = reward ? issue_reward(m, reward, source: "birthday") : nil
        # Hết hàng: để nguyên mốc năm, hôm nay quán nhập thêm thì quà vẫn kịp đi,
        # và không nói gì còn hơn báo một món quà không nằm trong ví khách.
        next if reward && !gifted
        m.update_columns(settings: m.settings.merge("birthday_year" => today.year))
        if gifted
          MemberNotifier.notify(m, "birthday", icon: "🎂", link: "/wallet?tab=owned", reward: reward.title)
        else
          MemberNotifier.notify(m, "birthday_plain", icon: "🎂", link: "/", shop: ws.name)
        end
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
