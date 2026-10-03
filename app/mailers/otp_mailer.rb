class OtpMailer < ApplicationMailer
  def login_code(challenge)
    @code = challenge.code
    @workspace = challenge.workspace
    # Sender display name = the shop's name (white-label); address is our
    # authenticated MAIL_FROM.
    from_addr = ENV.fetch("MAIL_FROM", "no-reply@quenly.tiumpower.com")
    # A phone-identified challenge carries no email in `identifier`; the
    # address, if any, comes off the member's profile.
    to_addr = challenge.delivery_email
    return if to_addr.blank?
    mail(to: to_addr,
         from: "#{@workspace.name} <#{from_addr}>",
         subject: "#{@workspace.name}: Mã đăng nhập #{@code}")
  end
end
