module MerchantHelper

  # ---------------------------------------------------------------------
  # Navigation. The admin design has SIX sidebar entries, one per flow, with
  # the individual screens as tabs under the page title. Every screen the shop
  # had before still lives in exactly one of them — this map is the only place
  # that decides where, so the sidebar and the tab strip can never disagree.
  #
  #   [nav_key, label, path, visible?]
  # ---------------------------------------------------------------------
  def merchant_sections
    manage = current_membership&.can_manage?
    [
      { key: :overview, icon: :layout, label: t("merchant.nav.sec_overview"), items: [
        [:dashboard, t("merchant.nav.dashboard"), merchant_root_path, true]
      ] },
      { key: :operations, icon: :store, label: t("merchant.nav.sec_operations"), items: [
        [:scanner,      t("merchant.nav.scanner"),      merchant_scanner_path,      true],
        [:transactions, t("merchant.nav.transactions"), merchant_transactions_path, true],
        [:outlets,      t("merchant.nav.outlets"),      merchant_outlets_path,      manage]
      ] },
      { key: :loyalty, icon: :award, label: t("merchant.nav.sec_loyalty"), items: [
        [:program,        t("merchant.nav.program"),      merchant_loyalty_program_path, manage],
        [:tiers,          t("merchant.nav.tiers"),        merchant_tiers_path,           manage],
        [:rewards,        t("merchant.nav.rewards"),      merchant_rewards_path,         manage],
        [:stamp_cards,    t("merchant.nav.stamp_cards"),  merchant_stamp_cards_admin_path, manage],
        [:missions_setup, t("merchant.nav.missions"),     merchant_missions_admin_path,  manage],
        [:games,          t("merchant.nav.games"),        merchant_games_admin_path,     manage]
      ] },
      { key: :customers, icon: :users, label: t("merchant.nav.sec_customers"), items: [
        [:customers, t("merchant.nav.customers"), merchant_customers_path, true],
        [:segments,  t("merchant.nav.segments"),  merchant_segments_path,  manage],
        [:feedback,  t("merchant.nav.feedback"),  merchant_feedback_path,  true]
      ] },
      # The design splits this section in two: campaigns, and everything that
      # sends a message (broadcasts + automations) behind one tab, which then
      # has its own pair of tabs.
      { key: :campaigns, icon: :megaphone, label: t("merchant.nav.sec_campaigns"), items: [
        [:campaigns, t("merchant.nav.campaigns"), merchant_campaigns_path,  manage],
        [:messages,  t("merchant.nav.messages"),  merchant_broadcasts_path, true]
      ] },
      { key: :settings, icon: :gear, label: t("merchant.nav.sec_settings"), items: [
        [:appearance, t("merchant.nav.appearance"), merchant_appearance_path,   manage],
        [:staff,      t("merchant.nav.staff"),      merchant_staff_index_path,  manage],
        [:domain,     t("merchant.nav.domain"),     merchant_domain_path,       manage],
        [:billing,    t("merchant.nav.billing"),    merchant_billing_path,      manage],
        [:account,    t("merchant.nav.account"),    merchant_account_path,      true]
      ] }
    ].map { |sec| sec.merge(items: sec[:items].select { |it| it[3] }) }
     .reject { |sec| sec[:items].empty? }
  end

  # Which of the six a screen belongs to, from its own nav_key.
  def merchant_section_for(nav)
    merchant_sections.find { |sec| sec[:items].any? { |it| it[0] == nav } }
  end

  # The tab strip under a page title: the other screens in the same section.
  # A section with a single screen needs no tabs.
  def merchant_section_tabs(nav)
    sec = merchant_section_for(nav)
    return nil if sec.nil? || sec[:items].size < 2
    sec[:items]
  end
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

  # Icon per campaign type, for the pick-one cards in the campaign editor. Keys
  # are Campaign::TYPES; a type without its own glyph falls back to the gift.
  CAMPAIGN_TYPE_ICONS = { "promo_voucher" => :qrcode, "double_points" => :sparkles,
                          "happy_hour" => :clock, "event" => :star,
                          "flash_mission" => :flame }.freeze
  def campaign_type_icon(key) = CAMPAIGN_TYPE_ICONS.fetch(key.to_s, :gift)

  # Icon per automation, same idea.
  AUTOMATION_ICONS = { "welcome" => :user, "birthday" => :gift, "winback" => :refresh }.freeze
  def automation_icon(key) = AUTOMATION_ICONS.fetch(key.to_s, :bell)
end
