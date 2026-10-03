# Sends OTP via Zalo Notification Service (ZNS) template messages through our
# own Zalo Official Account. OA access tokens expire (~1h) and refresh tokens
# ROTATE on each refresh, so both are stored durably in AppSetting.
#
# Required ENV (set once the OA + an approved OTP template exist):
#   ZALO_APP_ID, ZALO_APP_SECRET, ZALO_ZNS_TEMPLATE_ID, ZALO_OA_REFRESH_TOKEN
#   (optional) ZALO_ZNS_OTP_PARAM — the template's OTP parameter name (default "otp")
#
# See docs/ZALO_ZNS.md for how to obtain them.
class ZaloZns
  SEND_URL  = "https://business.openapi.zalo.me/message/template".freeze
  TOKEN_URL = "https://oauth.zaloapp.com/v4/oa/access_token".freeze

  REQUIRED = %w[ZALO_APP_ID ZALO_APP_SECRET ZALO_ZNS_TEMPLATE_ID].freeze

  def self.configured? = missing_env.empty?

  # Which credentials are still missing, for the admin screen. The refresh token
  # may come from ENV or from AppSetting (it rotates, so the stored one wins).
  def self.missing_env
    missing = REQUIRED.reject { |key| ENV[key].present? }
    if ENV["ZALO_OA_REFRESH_TOKEN"].blank? && AppSetting.get("zns_refresh_token").blank?
      missing << "ZALO_OA_REFRESH_TOKEN"
    end
    missing
  end

  def deliver(phone:, code:)
    to = PhoneFormat.vn84(phone)
    return failure("bad_phone") if to.blank?

    token = access_token
    return failure("no_token") if token.blank?

    payload = { phone: to, template_id: ENV["ZALO_ZNS_TEMPLATE_ID"],
                template_data: { ENV.fetch("ZALO_ZNS_OTP_PARAM", "otp") => code.to_s } }
    resp = OtpSender.connection.post(SEND_URL) do |req|
      req.headers["access_token"] = token
      req.body = JSON.generate(payload)
    end
    json = parse(resp.body)
    ok   = json["error"].to_i.zero?
    OtpSender::Result.new(ok: ok, provider: "zns",
                          vendor_id: json.dig("data", "msg_id"),
                          error: ok ? nil : "#{json['error']} #{json['message']}".strip)
  rescue => e
    Rails.logger.error("[OTP][zns] #{e.class}: #{e.message}")
    failure(e.class.name)
  end

  private

  def failure(error) = OtpSender::Result.new(ok: false, provider: "zns", error: error)

  def parse(body)
    JSON.parse(body.to_s)
  rescue JSON::ParserError
    {}
  end

  def access_token
    current = AppSetting.get("zns_access_token")
    expiry  = AppSetting.get("zns_token_expiry").to_i
    return current if current.present? && Time.now.to_i < (expiry - 120)
    refresh!
  end

  # Zalo INVALIDATES the old refresh token on every refresh. Without a lock,
  # two workers refreshing at the same time means the loser persists a token
  # Zalo has already revoked — and ZNS is then dead until someone pastes a new
  # refresh token in by hand. The advisory lock is per-database, so it covers
  # every puma worker and Sidekiq alike.
  def refresh!
    token = nil
    AppSetting.transaction do
      ActiveRecord::Base.connection.execute(
        "SELECT pg_advisory_xact_lock(hashtext('zns_token_refresh'))"
      )

      current = AppSetting.get("zns_access_token")
      expiry  = AppSetting.get("zns_token_expiry").to_i
      if current.present? && Time.now.to_i < (expiry - 120)
        token = current # another process refreshed while we waited for the lock
      else
        token = perform_refresh!
      end
    end
    token
  end

  def perform_refresh!
    refresh_token = AppSetting.get("zns_refresh_token").presence || ENV["ZALO_OA_REFRESH_TOKEN"]
    return nil if refresh_token.blank?

    resp = OtpSender.connection(headers: { "Content-Type" => "application/x-www-form-urlencoded" })
                    .post(TOKEN_URL) do |req|
      req.headers["secret_key"] = ENV["ZALO_APP_SECRET"]
      req.body = URI.encode_www_form(refresh_token: refresh_token,
                                     app_id: ENV["ZALO_APP_ID"],
                                     grant_type: "refresh_token")
    end
    json = parse(resp.body)
    if json["access_token"].blank?
      Rails.logger.error("[OTP][zns] token refresh rejected: #{json['error']} #{json['message']}")
      return nil
    end

    # Keep the superseded token: if a rotation ever gets clobbered, this makes
    # it recoverable by hand instead of needing a fresh OA authorization.
    AppSetting.set("zns_refresh_token_prev", refresh_token)
    AppSetting.set("zns_access_token",  json["access_token"])
    AppSetting.set("zns_refresh_token", json["refresh_token"]) if json["refresh_token"].present?
    AppSetting.set("zns_token_expiry",  (Time.now.to_i + json["expires_in"].to_i).to_s)
    json["access_token"]
  rescue => e
    Rails.logger.error("[OTP][zns] token refresh #{e.class}: #{e.message}")
    nil
  end
end
