class StaffMailer < ApplicationMailer
  # Invite a newly-added staff member: email a link to set their password.
  def invite(user, workspace, token)
    @workspace = workspace
    @name = user.name
    host = if Rails.env.production? && workspace.subdomain.present?
      "#{workspace.subdomain}.#{ApplicationController::PLATFORM_HOST}"
    else
      Rails.application.config.action_mailer.default_url_options[:host] || "localhost:3008"
    end
    @url = edit_user_password_url(reset_password_token: token, host: host)
    mail(to: user.email,
         from: "#{workspace.name} <#{ENV.fetch('MAIL_FROM', 'no-reply@loyalty.tiumpower.com')}>",
         subject: "#{workspace.name}: Lời mời truy cập bảng điều khiển")
  end
end
