require "faraday"

# ActionMailer delivery method that sends via Brevo's HTTP API (over HTTPS/443),
# so it works even where outbound SMTP ports are blocked (e.g. DigitalOcean).
# Enabled when ENV["BREVO_API_KEY"] is present (see production.rb + initializer).
class BrevoMailDelivery
  ENDPOINT = "https://api.brevo.com/v3/smtp/email".freeze

  def initialize(settings = {})
    @settings = settings
  end

  def deliver!(mail)
    key = ENV["BREVO_API_KEY"]
    return if key.blank?

    addr       = mail.header[:from]&.addrs&.first
    from_email = addr&.address.presence || Array(mail.from).first || ENV.fetch("MAIL_FROM", "no-reply@loyalty.tiumpower.com")
    from_name  = addr&.display_name.presence || ENV.fetch("MAIL_FROM_NAME", "Dynamic Loyalty")
    body = {
      sender:      { email: from_email, name: from_name },
      to:          Array(mail.to).map { |e| { email: e } },
      subject:     mail.subject,
      htmlContent: html_body(mail),
      textContent: text_body(mail)
    }.compact

    resp = Faraday.post(ENDPOINT, JSON.generate(body),
                        "api-key" => key, "Content-Type" => "application/json", "Accept" => "application/json")
    if resp.status >= 300
      Rails.logger.error("[Brevo] #{resp.status}: #{resp.body}")
      raise "Brevo delivery failed (#{resp.status})"
    end
    Rails.logger.info("[Brevo] sent to=#{Array(mail.to).join(',')} status=#{resp.status}")
  end

  private

  def html_body(mail)
    mail.html_part&.body&.decoded || (mail.mime_type == "text/html" ? mail.body.decoded : nil)
  end

  def text_body(mail)
    mail.text_part&.body&.decoded || (mail.mime_type == "text/plain" ? mail.body.decoded : nil)
  end
end
