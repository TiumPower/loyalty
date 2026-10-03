# Sends OTP as a Zalo ZNS template message through the eSMS reseller, for when
# we do not (yet) have our own approved Zalo OA. eSMS holds the OA relationship;
# we only hand it a template id and the code.
#
# Required ENV:
#   ESMS_API_KEY, ESMS_SECRET_KEY, ESMS_OA_ID, ESMS_TEMPLATE_ID
#   (optional) ESMS_OTP_PARAM (default "otp"), ESMS_CAMPAIGN_ID, ESMS_SANDBOX
#
# We deliberately do NOT use eSMS's auto-gencode endpoint: it generates the code
# itself, which would move verification out of OtpChallenge and leave us unable
# to expire or rate-limit a code we never saw.
class EsmsZns
  SEND_URL = "https://rest.esms.vn/MainService.svc/json/SendZaloMessage_V6/".freeze
  REQUIRED = %w[ESMS_API_KEY ESMS_SECRET_KEY ESMS_OA_ID ESMS_TEMPLATE_ID].freeze
  OK_CODE  = "100".freeze

  def self.configured? = missing_env.empty?

  def self.missing_env = REQUIRED.reject { |key| ENV[key].present? }

  def deliver(phone:, code:)
    to = PhoneFormat.vn84(phone)
    return failure("bad_phone") if to.blank?

    resp = OtpSender.connection.post(SEND_URL) { |req| req.body = JSON.generate(body(to, code)) }
    json = parse(resp.body)
    ok   = json["CodeResult"].to_s == OK_CODE
    OtpSender::Result.new(ok: ok, provider: "esms", vendor_id: json["SMSID"],
                          error: ok ? nil : "#{json['CodeResult']} #{json['ErrorMessage']}".strip)
  rescue => e
    Rails.logger.error("[OTP][esms] #{e.class}: #{e.message}")
    failure(e.class.name)
  end

  private

  def body(to, code)
    payload = {
      ApiKey: ENV["ESMS_API_KEY"], SecretKey: ENV["ESMS_SECRET_KEY"],
      Phone: to, OAID: ENV["ESMS_OA_ID"], TempID: ENV["ESMS_TEMPLATE_ID"],
      TempData: { ENV.fetch("ESMS_OTP_PARAM", "otp") => code.to_s },
      # eSMS de-duplicates on RequestId for 24h, which is what stops a Faraday
      # retry from being charged (and delivered) twice.
      RequestId: SecureRandom.uuid,
      Sandbox: ActiveModel::Type::Boolean.new.cast(ENV["ESMS_SANDBOX"]) ? "1" : "0"
    }
    payload[:campaignid] = ENV["ESMS_CAMPAIGN_ID"] if ENV["ESMS_CAMPAIGN_ID"].present?
    payload
  end

  def failure(error) = OtpSender::Result.new(ok: false, provider: "esms", error: error)

  def parse(body)
    JSON.parse(body.to_s)
  rescue JSON::ParserError
    {}
  end
end
