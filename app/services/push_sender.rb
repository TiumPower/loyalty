require "web_push"

# Sends Web Push notifications to members' PWA subscriptions. No-ops safely when
# VAPID keys aren't configured (mirrors PayosService#configured?).
module PushSender
  module_function

  def configured?
    ENV["VAPID_PUBLIC_KEY"].present? && ENV["VAPID_PRIVATE_KEY"].present?
  end

  def public_key = ENV["VAPID_PUBLIC_KEY"].to_s

  def vapid
    { subject:     ENV.fetch("VAPID_SUBJECT", "mailto:admin@loyalty.tiumpower.com"),
      public_key:  ENV["VAPID_PUBLIC_KEY"],
      private_key: ENV["VAPID_PRIVATE_KEY"] }
  end

  # Deliver to every push subscription of the given members (current tenant).
  def deliver_to(member_ids, title:, body:, path: "/", icon: nil)
    return unless configured? && member_ids.present?
    payload = JSON.generate(title: title, body: body.to_s, path: path, icon: icon)
    PushSubscription.where(member_id: member_ids).find_each { |sub| send_one(sub, payload) }
  end

  def send_one(sub, payload)
    WebPush.payload_send(message: payload, endpoint: sub.endpoint,
                         p256dh: sub.p256dh, auth: sub.auth, vapid: vapid, urgency: "normal")
  rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription, WebPush::Unauthorized
    sub.destroy
  rescue => e
    Rails.logger.error("[PushSender] #{e.class}: #{e.message}")
  end
end
