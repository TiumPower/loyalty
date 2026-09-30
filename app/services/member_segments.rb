# Preset customer segments for CRM targeting. Each returns a tenant-scoped
# Member relation (call within ActsAsTenant.with_tenant / a scoped request).
module MemberSegments
  module_function

  PRESETS = {
    "all"           => { label: "Tất cả khách",            icon: "👥" },
    "vip"           => { label: "Khách VIP",               icon: "👑" },
    "new"           => { label: "Khách mới trong tuần",    icon: "✨" },
    "has_points"    => { label: "Có điểm chưa đổi",        icon: "💰" },
    "near_stamp"    => { label: "Sắp hoàn thành thẻ tem",  icon: "🎟️" },
    "birthday_week" => { label: "Sinh nhật tuần này",      icon: "🎂" },
    "birthday"      => { label: "Sinh nhật tháng này",     icon: "🎉" },
    "at_risk"       => { label: "Sắp rời bỏ (>30 ngày)",   icon: "⚠️" },
    "at_risk_60"    => { label: "Rời bỏ (>60 ngày)",       icon: "🚶" }
  }.freeze

  def label(key) = I18n.t("merchant.segments.#{key}", default: (PRESETS.dig(key, :label) || "Tất cả khách"))
  def icon(key)  = PRESETS.dig(key, :icon) || "👥"

  # A preset segment optionally narrowed by branch (outlet) and a name/email/phone
  # search — the SAME filters the Customers list exposes. Both the customer table and
  # the broadcast targeting go through here so the "will send to N" count always
  # matches the visible list. Call within a tenant-scoped request.
  def audience(segment:, outlet_id: nil, q: nil, tier: nil)
    scope = resolve(PRESETS.key?(segment) ? segment : "all")
    if outlet_id.present?
      scope = scope.where(id: Purchase.not_voided.where(outlet_id: outlet_id).select(:member_id))
    end
    scope = scope.where(tier_key: tier) if tier.present?
    term = q.to_s.strip
    if term.present?
      like = "%#{term}%"
      scope = scope.where("members.name ILIKE :q OR members.email ILIKE :q OR members.phone ILIKE :q", q: like)
    end
    scope
  end

  # A human-readable name for a (possibly filtered) audience. Always returns a
  # non-empty label — for a filtered custom group with no preset name it composes a
  # temporary one from the active filters (e.g. "Tất cả khách · Gấu Coffee · tìm "lê"").
  def audience_label(segment:, outlet: nil, q: nil, tier: nil)
    parts = [ label(PRESETS.key?(segment) ? segment : "all") ]
    parts << outlet.name if outlet.respond_to?(:name) && outlet.name.present?
    parts << "hạng #{tier.to_s.capitalize}" if tier.present?
    term = q.to_s.strip
    parts << "tìm “#{term}”" if term.present?
    parts.join(" · ")
  end

  def resolve(key)
    case key
    when "vip"           then vip
    when "new"           then new_members
    when "has_points"    then has_points
    when "near_stamp"    then near_stamp
    when "birthday_week" then birthday_week
    when "birthday"      then birthday
    when "at_risk"       then at_risk(30)
    when "at_risk_60"    then at_risk(60)
    else Member.all
    end
  end

  def vip = Member.where(tier_key: %w[gold diamond])

  def new_members = Member.where("created_at >= ?", 7.days.ago)

  # Members still holding unredeemed points (a nudge to come redeem).
  def has_points = Member.where("points_balance > 0")

  # 1–2 stamps away from completing a stamp card.
  def near_stamp
    ids = StampCardMembership.joins(:stamp_card)
            .where("stamp_card_memberships.count > 0 AND " \
                   "stamp_card_memberships.count >= stamp_cards.target_count - 2 AND " \
                   "stamp_card_memberships.count < stamp_cards.target_count")
            .distinct.pluck(:member_id)
    Member.where(id: ids)
  end

  def birthday
    Member.where.not(birthday: nil).where("EXTRACT(MONTH FROM birthday) = ?", Date.current.month)
  end

  def birthday_week
    days = (0..6).map { |i| (Date.current + i).strftime("%m-%d") }
    Member.where.not(birthday: nil).where("to_char(birthday, 'MM-DD') IN (?)", days)
  end

  # No purchase in the last `days` days, but has purchased before.
  def at_risk(days = 30)
    active_ids = Purchase.not_voided.where("created_at >= ?", days.days.ago).distinct.pluck(:member_id)
    ever_ids   = Purchase.not_voided.distinct.pluck(:member_id)
    Member.where(id: ever_ids - active_ids)
  end

  def counts
    PRESETS.keys.index_with { |k| resolve(k).count }
  end
end
