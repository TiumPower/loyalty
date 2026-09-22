class AdminMailer < ApplicationMailer
  # Notify every super-admin that a new workspace just signed up.
  def new_workspace(workspace)
    @workspace = workspace
    @admin_url = "https://#{ApplicationController::PLATFORM_HOST}/admin/workspaces/#{workspace.to_param}"
    recipients = AdminUser.pluck(:email).compact_blank
    return if recipients.empty?
    mail(to: recipients, from: platform_from,
         subject: "🎉 Workspace mới: #{workspace.name} (#{workspace.subdomain})")
  end

  private

  def platform_from = %(Dynamic Loyalty <#{ENV.fetch("MAIL_FROM", "no-reply@loyalty.tiumpower.com")}>)
end
