class ApplicationMailer < ActionMailer::Base
  default from: %(Dynamic Loyalty <#{ENV.fetch("MAIL_FROM", "no-reply@loyalty.tiumpower.com")}>)
  layout "mailer"
end
