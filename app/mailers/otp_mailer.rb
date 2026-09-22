class OtpMailer < ApplicationMailer
  def login_code(challenge)
    @code = challenge.code
    @workspace = challenge.workspace
    # Sender display name = the shop's name (white-label); address is our
    # authenticated MAIL_FROM.
    from_addr = ENV.fetch("MAIL_FROM", "no-reply@loyalty.tiumpower.com")
    mail(to: challenge.email,
         from: "#{@workspace.name} <#{from_addr}>",
         subject: "#{@workspace.name}: Mã đăng nhập #{@code}")
  end
end
