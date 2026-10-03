# Pluggable OTP delivery over Zalo. Two adapters, picked by ENV:
#
#   ZaloZns — our own Zalo Official Account via ZNS (cheaper, token is ours)
#   EsmsZns — the eSMS reseller (no OA approval needed to get started)
#
# ENV:
#   OTP_ZALO_PROVIDER=zns|esms|none   blank = auto-detect; "none" = hard off
#   OTP_PROVIDER_FALLBACK=true        on failure, try the other configured one
module OtpSender
  # A boolean would throw away the two things a merchant always asks about a
  # missing code: which provider ran, and what it said.
  Result = Struct.new(:ok, :provider, :error, :vendor_id, keyword_init: true) do
    def ok? = !!ok
  end

  ADAPTERS = { "zns" => "ZaloZns", "esms" => "EsmsZns" }.freeze

  module_function

  def mode = ENV.fetch("OTP_ZALO_PROVIDER", "").strip.downcase

  def adapter(key) = ADAPTERS[key]&.safe_constantize

  # Which providers to consider, in order. The official OA goes first when both
  # are configured: it is cheaper per message and the credentials are ours.
  def keys
    return [] if mode == "none"
    return [mode] if ADAPTERS.key?(mode)
    ADAPTERS.keys.select { |k| adapter(k)&.configured? }
  end

  # "At least one provider has all its credentials." Called on every render of
  # the login and verify screens, so it only ever reads ENV and AppSetting —
  # never the network.
  def configured? = keys.any? { |k| adapter(k)&.configured? }

  def primary = keys.find { |k| adapter(k)&.configured? }

  def deliver(phone:, code:)
    order = [primary].compact
    order += (keys - order).select { |k| adapter(k)&.configured? } if fallback?
    return Result.new(ok: false, error: "not_configured") if order.empty?

    result = nil
    order.each do |key|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result  = adapter(key).new.deliver(phone: phone, code: code)
      elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

      Rails.logger.info("[OTP] provider=#{key} to=#{PhoneFormat.mask(phone)} ok=#{result.ok?} " \
                        "vendor_id=#{result.vendor_id} err=#{result.error} ms=#{elapsed}")
      return result if result.ok?

      # One fingerprint per (provider, error) so a vendor outage is one issue
      # to look at, not one per customer who tried to log in during it.
      if defined?(Sentry)
        Sentry.capture_message("OTP delivery failed", level: :warning,
                               fingerprint: ["otp-delivery", key, result.error.to_s],
                               extra: { provider: key, error: result.error })
      end
    end
    result
  end

  def fallback? = ActiveModel::Type::Boolean.new.cast(ENV["OTP_PROVIDER_FALLBACK"])

  # Shared Faraday connection settings for the adapters. Timeouts are not
  # optional here: several Rails apps share one small box, and a hung vendor
  # socket inside a request pins a puma worker until it gives up.
  def connection(headers: { "Content-Type" => "application/json" })
    Faraday.new(headers: headers, request: { open_timeout: 3, timeout: 7 }) do |f|
      # One retry only. A send that lands after the customer gave up and asked
      # for a new code costs money and delivers a stale code.
      f.request :retry, max: 1, interval: 0.3,
                        retry_statuses: [429, 502, 503, 504], methods: %i[post]
      f.adapter Faraday.default_adapter
    end
  end
end
