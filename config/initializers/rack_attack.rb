# Basic abuse protection for auth endpoints (OTP + logins).
# Focused throttles only — no broad IP throttle, to avoid false-positives on
# the customer app's polling. Uses a shared Redis store across puma workers.
return unless defined?(Rack::Attack)

class Rack::Attack
  begin
    self.cache.store = ActiveSupport::Cache::RedisCacheStore.new(
      url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"),
      namespace: "rack_attack", error_handler: ->(*) {}
    )
  rescue StandardError => e
    Rails.logger.warn("[RackAttack] Redis store unavailable, using memory: #{e.class}")
  end

  safelist("localhost") { |req| %w[127.0.0.1 ::1].include?(req.ip) }

  customer_login = ->(req) { req.post? && req.path.end_with?("/login") && !req.path.start_with?("/merchant", "/admin") }

  # Customer OTP issue: limit per email (anti email-bomb) and per IP.
  throttle("otp/email", limit: 5, period: 10.minutes) do |req|
    if customer_login.call(req)
      email = req.params["email"].to_s.strip.downcase
      "otp-email:#{email}" if email.present?
    end
  end
  throttle("otp/ip", limit: 20, period: 10.minutes) { |req| req.ip if customer_login.call(req) }

  # Customer OTP verify: cap guesses per IP (model already caps per challenge).
  throttle("otp-verify/ip", limit: 30, period: 10.minutes) do |req|
    req.ip if req.post? && req.path.end_with?("/verify")
  end

  # Merchant / Admin login (password): cap attempts per IP.
  throttle("login/ip", limit: 15, period: 20.minutes) do |req|
    req.ip if req.post? && %w[/merchant/login /admin/login].include?(req.path)
  end

  # Merchant self-serve signup: the form takes an email + password, so an
  # unthrottled endpoint doubles as a password-guessing oracle against existing
  # merchant accounts (and lets one IP spam workspaces). Cap per IP and per email.
  merchant_signup = ->(req) { req.post? && req.path == "/merchant/signup" }
  throttle("signup/ip", limit: 10, period: 1.hour) { |req| req.ip if merchant_signup.call(req) }
  throttle("signup/email", limit: 5, period: 1.hour) do |req|
    if merchant_signup.call(req)
      email = req.params["email"].to_s.strip.downcase
      "signup-email:#{email}" if email.present?
    end
  end

  # Password reset: unthrottled, this both probes for registered addresses and
  # lets anyone bomb a known merchant's inbox with reset mail.
  pw_reset = ->(req) { req.post? && %w[/merchant/password /admin/password].include?(req.path) }
  throttle("pwreset/ip", limit: 10, period: 1.hour) { |req| req.ip if pw_reset.call(req) }
  throttle("pwreset/email", limit: 4, period: 1.hour) do |req|
    if pw_reset.call(req)
      email = req.params.dig("user", "email").presence ||
              req.params.dig("admin_user", "email")
      "pwreset-email:#{email.to_s.strip.downcase}" if email.present?
    end
  end

  self.throttled_responder = lambda do |req|
    period = (req.env["rack.attack.match_data"] || {})[:period]
    [429, { "Content-Type" => "text/plain", "Retry-After" => period.to_s },
     ["Quá nhiều yêu cầu. Vui lòng thử lại sau ít phút. / Too many requests. Please try again shortly."]]
  end
end
