module MerchantHelper
  # Renders a "Back" control into the merchant top bar (see layouts/merchant.html.erb).
  # It returns to the real previous page via browser history, falling back to `url`
  # when there is no history (e.g. the page was opened directly). Call once near the
  # top of any drill-down screen: `<% merchant_back merchant_campaigns_path %>`.
  def merchant_back(url, label = nil)
    label ||= t("merchant.back")
    content_for :back, link_to("← #{label}", url,
      data: { controller: "goback", action: "click->goback#back" },
      style: "display:inline-flex; align-items:center; gap:4px; color:var(--ink-2); " \
             "text-decoration:none; font-size:13px; font-weight:600; padding:6px 12px; " \
             "border:1px solid var(--line); border-radius:999px; white-space:nowrap; background:#fff;")
    nil
  end

  # Label for a reward inside a picker ("Thưởng: Cà phê"), flagged when the prize
  # has run out — a merchant attaching a sold-out reward to a stamp card would
  # otherwise only find out when customers complete the card and get nothing.
  def reward_option_label(reward)
    label = t("merchant.gami.reward_opt", title: reward.title)
    label += t("merchant.campaigns.reward_opt_sold_out") unless reward.in_stock?
    label
  end
end
