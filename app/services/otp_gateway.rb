# What the super admin needs to know and do about the Zalo OTP gateway:
# whether it is wired up, what is still missing, and whether a real send to a
# real phone actually works.
#
# The test send exists because everything else about this gateway can look
# correct while delivery silently fails — a template not yet approved, a wrong
# OA id, an expired refresh token. One button, one real message, a clear answer.
module OtpGateway
  module_function

  def status
    {
      mode:        OtpSender.mode.presence || "auto",
      provider:    OtpSender.primary,
      configured:  OtpSender.configured?,
      fallback:    OtpSender.fallback?,
      missing:     OtpSender::ADAPTERS.keys.index_with { |k| OtpSender.adapter(k).missing_env },
      verified_at: (t = AppSetting.get("zns_verified_at").presence) && Time.zone.at(t.to_i),
      last_test:   AppSetting.get("otp_last_test").presence,
      token_expiry: (e = AppSetting.get("zns_token_expiry").presence) && Time.zone.at(e.to_i)
    }
  end

  # Sends a real OTP-shaped message, synchronously, and records the outcome so
  # the screen can show it after the redirect.
  def test_send(phone)
    local = Member.canonical_phone(phone)
    unless local&.match?(/\A0\d{8,10}\z/)
      return OtpSender::Result.new(ok: false, error: "bad_phone")
    end

    result = OtpSender.deliver(phone: local, code: format("%06d", SecureRandom.random_number(1_000_000)))
    AppSetting.set("otp_last_test", [
      Time.current.iso8601, PhoneFormat.mask(local), result.provider,
      result.ok? ? "ok" : "lỗi: #{result.error}"
    ].join(" · "))
    result
  end

  # Rotating refresh tokens means the ENV value goes stale after the first
  # refresh, so the admin screen has to be able to paste a fresh one. Clearing
  # the access token forces the next send to refresh with the new one.
  def store_refresh_token(token)
    return false if token.blank?
    AppSetting.set("zns_refresh_token", token.strip)
    AppSetting.set("zns_access_token", "")
    AppSetting.set("zns_token_expiry", "0")
    true
  end
end
