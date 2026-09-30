# One way into a member's inbox: the stored notification plus the push that
# announces it.
#
# It exists because every producer had grown its own copy of the same four
# lines, and half of them wrote the title and body as Vietnamese literals. A
# member whose app is in English was told in Vietnamese that their points were
# about to expire. Copy now goes through `customer.notices.*` in both locale
# files, rendered in *the member's* locale rather than whoever's request or
# background job happened to trigger it.
module MemberNotifier
  module_function

  # key   — a leaf under `customer.notices`, e.g. "tier_up" → .title / .body
  # vars  — interpolations for both strings
  # link  — in-app path the row opens
  def notify(member, key, link:, icon: nil, kind: "reward", **vars)
    return if member.nil?
    ws = member.workspace
    title, body = I18n.with_locale(locale_for(member)) do
      [I18n.t("customer.notices.#{key}.title", **vars),
       I18n.t("customer.notices.#{key}.body", **vars)]
    end
    member.notifications.create!(workspace: ws, kind: kind, title: title, body: body,
                                 icon: icon, deep_link: link)
    PushJob.perform_later(ws.id, [member.id], title, body, link) if PushSender.configured?
    true
  rescue => e
    Rails.logger.error("[MemberNotifier] #{key}: #{e.class} #{e.message}")
    false
  end

  # The member's own language, falling back to the shop's default rather than to
  # whatever locale the current request or cron job is running in.
  def locale_for(member)
    wanted = [member.locale, member.workspace&.default_locale_sym].compact_blank.map(&:to_sym)
    (wanted & I18n.available_locales).first || I18n.default_locale
  end
end
