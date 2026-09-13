# Progresses gamification state after a purchase: stamps, spend/visit missions,
# and badges. Defensive — never let a gamification error break earning.
module Gamification
  module_function

  def after_purchase(purchase)
    member = purchase.member
    ws = purchase.workspace
    return unless ws.program.gamification_enabled

    advance_stamps(member, ws)
    advance_missions(member, ws, purchase)
    evaluate_badges(member, ws)
  rescue => e
    Rails.logger.error("[Gamification] #{e.class}: #{e.message}")
  end

  # ---- Reversal (a bill was voided) --------------------------------------
  # Best-effort undo of what after_purchase granted. Deliberately conservative:
  # a stamp card that has since COMPLETED (and issued a voucher the customer may
  # already have used) is left alone, as is a mission whose points were claimed.
  # Those cases are rare — a void almost always happens seconds after the
  # mistake — and silently clawing back a reward is worse than a stray stamp.
  def reverse_purchase(purchase)
    ws = purchase.workspace
    return unless ws.program.gamification_enabled
    member = purchase.member
    reverse_stamps(member, ws)
    reverse_missions(member, ws, purchase)
  rescue => e
    Rails.logger.error("[Gamification] reverse_purchase: #{e.class} #{e.message}")
  end

  def reverse_stamps(member, ws)
    ws.stamp_cards.active.each do |card|
      sm = StampCardMembership.find_by(member_id: member.id, stamp_card_id: card.id)
      next if sm.nil?
      sm.with_lock { sm.update!(count: sm.count - 1) if sm.count.positive? }
    end
  end

  def reverse_missions(member, ws, purchase)
    ws.missions.active.each do |mission|
      next unless %w[spend visit].include?(mission.mission_type)
      # Roll back the bucket the purchase landed in, not today's, in case the
      # void crosses a daily/weekly boundary.
      key = mission.current_period_key(purchase.created_at)
      mp  = mission.mission_progresses.find_by(member_id: member.id, period_key: key)
      next if mp.nil? || mp.completed? # already paid out — leave it
      step = mission.mission_type == "spend" ? purchase.amount.to_i : 1
      mp.update!(progress: [mp.progress.to_i - step, 0].max)
    end
  end

  def advance_stamps(member, ws)
    ws.stamp_cards.active.each do |card|
      next unless card.running?
      result = card.membership_for(member).add_stamp!
      notify_stamp_reward(member, ws, card, result[:voucher]) if result[:completed] && result[:voucher]
    end
  end

  # Let the customer know a stamp card completed and a reward landed in their
  # wallet (in-app inbox + push) — otherwise the voucher appears silently.
  def notify_stamp_reward(member, ws, card, voucher)
    reward_name = voucher.reward&.title
    title = "Bạn vừa nhận quà! 🎁"
    body  = "Thẻ tem “#{card.title}” đã hoàn thành — #{reward_name} đã vào ví của bạn."
    Notification.create!(workspace: ws, member: member, kind: "reward",
                         title: title, body: body, icon: "🎁",
                         deep_link: "/vouchers/#{voucher.id}")
    PushJob.perform_later(ws.id, [member.id], title, body, "/vouchers/#{voucher.id}") if PushSender.configured?
  rescue => e
    Rails.logger.error("[Gamification] notify_stamp_reward: #{e.class} #{e.message}")
  end

  def advance_missions(member, ws, purchase)
    ws.missions.active.each do |mission|
      case mission.mission_type
      when "spend" then mission.progress_for(member).tap { |mp| mp.save! if mp.new_record? }.advance!(purchase.amount)
      when "visit" then mission.progress_for(member).tap { |mp| mp.save! if mp.new_record? }.advance!(1)
      end
    end
  end

  def evaluate_badges(member, ws)
    earned_ids = member.member_badges.pluck(:badge_id)
    ws.badges.where.not(id: earned_ids).each do |badge|
      next unless badge.earned_by?(member)
      mb = MemberBadge.create!(workspace: ws, member: member, badge: badge, earned_at: Time.current)
      voucher = nil
      # Bonus points for earning the badge (once), if the merchant set any.
      if badge.reward_points.to_i.positive?
        PointTransaction.create!(workspace: ws, member: member, kind: "mission",
                                 amount: badge.reward_points, source: mb,
                                 note: "🏅 #{badge.name}")
        member.recompute_points!
      end
      # Gift voucher for earning the badge (once), if the merchant attached one.
      # Respect the reward's own stock — a badge gift used to be issued
      # regardless of how few the merchant said there were.
      if badge.reward_id.present? && (reward = badge.reward) && reward.claim_stock!
        voucher = Voucher.create!(workspace: ws, member: member, reward: reward,
                                  source: "campaign", state: "active", points_spent: 0,
                                  expires_at: reward.voucher_expiry_from)
      end
      notify_badge_earned(member, ws, badge, voucher)
    end
  end

  # Let the customer know they just unlocked a badge — and what reward came with
  # it (bonus points and/or a voucher in their wallet). Without this the badge and
  # its reward would appear silently. Deep-links to the voucher when one was gifted,
  # otherwise to the badges screen.
  def notify_badge_earned(member, ws, badge, voucher)
    parts = []
    parts << "+#{badge.reward_points} điểm" if badge.reward_points.to_i.positive?
    parts << "#{voucher.reward&.title} đã vào ví" if voucher
    reward_line = parts.any? ? " — #{parts.join(" · ")}." : "."
    title = "Huy hiệu mới! #{badge.display_icon}"
    body  = "Bạn vừa đạt huy hiệu “#{badge.name}”#{reward_line}"
    deep_link = voucher ? "/vouchers/#{voucher.id}" : "/badges"
    Notification.create!(workspace: ws, member: member, kind: "reward",
                         title: title, body: body, icon: badge.display_icon,
                         deep_link: deep_link)
    PushJob.perform_later(ws.id, [member.id], title, body, deep_link) if PushSender.configured?
  rescue => e
    Rails.logger.error("[Gamification] notify_badge_earned: #{e.class} #{e.message}")
  end
end
