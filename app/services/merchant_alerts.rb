# Raises the alerts that show up in the merchant's bell menu.
#
# Design rules kept deliberately tight, because an inbox that cries wolf gets
# ignored and then the one alert that mattered is missed too:
#   * only things the merchant can DO something about
#   * never one alert per transaction — repeats collapse on `dedup_key`
#   * a failure here must never break the customer action that triggered it
module MerchantAlerts
  module_function

  def push(workspace, kind:, title:, body: nil, icon: nil, link: nil,
           level: "info", dedup_key: nil)
    return nil if workspace.nil?
    ActsAsTenant.with_tenant(workspace) do
      return nil if dedup_key.present? && MerchantAlert.exists?(dedup_key: dedup_key)
      MerchantAlert.create!(workspace: workspace, kind: kind, title: title, body: body,
                            icon: icon, link: link, level: level, dedup_key: dedup_key)
    end
  rescue ActiveRecord::RecordNotUnique
    nil # lost a race against a concurrent identical alert — that's fine
  rescue => e
    Rails.logger.error("[MerchantAlerts] #{kind}: #{e.class} #{e.message}")
    nil
  end

  # A customer left a review. Low scores are escalated — that's the one the owner
  # needs to see today, while they can still win the customer back.
  def new_rating(rating)
    return if rating.nil?
    low = rating.stars <= 3
    excerpt = rating.comment.to_s.strip
    excerpt = "#{excerpt[0, 140]}…" if excerpt.length > 140
    push(rating.workspace,
         kind: "rating",
         level: (rating.stars <= 2 ? "danger" : (low ? "warn" : "info")),
         icon: low ? "⚠️" : "⭐",
         title: I18n.t("merchant.alerts.rating_title",
                       stars: rating.stars, name: rating.member&.display_name),
         body: excerpt.presence,
         link: "/merchant/feedback")
  end

  # A redeemable reward just ran out. Keyed on the stock level so restocking and
  # running out again raises a fresh alert, but a busy evening doesn't raise ten.
  def reward_out_of_stock(reward)
    return if reward.nil? || reward.stock.nil? || reward.in_stock?
    push(reward.workspace,
         kind: "reward_stock", level: "warn", icon: "📦",
         title: I18n.t("merchant.alerts.stock_title", title: reward.title),
         body: I18n.t("merchant.alerts.stock_body", n: reward.redeemed_count),
         link: "/merchant/rewards",
         dedup_key: "reward_oos:#{reward.id}:#{reward.stock}")
  end

  # A customer filled a stamp card but the prize has run out, so the card is
  # being held. This is money waiting at the counter — keyed on the stock level
  # so restocking and running out again alerts afresh, without one per stamp.
  def stamp_reward_exhausted(card)
    reward = card&.reward or return
    push(card.workspace,
         kind: "reward_stock", level: "danger", icon: "⏳",
         title: I18n.t("merchant.alerts.stamp_held_title", card: card.title),
         body: I18n.t("merchant.alerts.stamp_held_body", title: reward.title),
         link: "/merchant/rewards",
         dedup_key: "stamp_held:#{card.id}:#{reward.id}:#{reward.stock}")
  end

  # A photo-proof mission is waiting for a human. One alert per pending queue per
  # day is enough to get someone to open it.
  def mission_submission(progress)
    return if progress.nil?
    push(progress.workspace,
         kind: "mission_submission", level: "info", icon: "🕐",
         title: I18n.t("merchant.alerts.submission_title"),
         body: I18n.t("merchant.alerts.submission_body", title: progress.mission&.title),
         link: "/merchant/mission_submissions",
         dedup_key: "submissions:#{progress.workspace_id}:#{Date.current}")
  end
end
