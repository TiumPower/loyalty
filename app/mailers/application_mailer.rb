class ApplicationMailer < ActionMailer::Base
  default from: %(Quenly <#{ENV.fetch("MAIL_FROM", "no-reply@loyalty.tiumpower.com")}>)
  layout "mailer"
end
