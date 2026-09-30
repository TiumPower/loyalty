class ApplicationMailer < ActionMailer::Base
  default from: %(Quenly <#{ENV.fetch("MAIL_FROM", "no-reply@quenly.tiumpower.com")}>)
  layout "mailer"
end
