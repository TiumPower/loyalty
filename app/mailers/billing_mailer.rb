class BillingMailer < ApplicationMailer
  # New month's invoice is ready — remind the owner to pay (PayOS link if we
  # have one, else the billing page).
  def invoice_ready(invoice)
    @invoice   = invoice
    @workspace = invoice.workspace
    @pay_url   = invoice.checkout_url.presence || billing_page_url(@workspace)
    return if @workspace.billing_email.blank?
    mail(to: @workspace.billing_email, from: platform_from,
         subject: "Hoá đơn dịch vụ tháng mới — #{@workspace.name}")
  end

  # Shop was auto-suspended after the grace period.
  def suspended(workspace)
    @workspace = workspace
    @pay_url   = billing_page_url(workspace)
    return if workspace.billing_email.blank?
    mail(to: workspace.billing_email, from: platform_from,
         subject: "Cửa hàng đã tạm ngưng do chưa thanh toán — #{workspace.name}")
  end

  private

  def platform_from = %(Dynamic Loyalty <#{ENV.fetch("MAIL_FROM", "no-reply@loyalty.tiumpower.com")}>)

  def billing_page_url(ws)
    host = ws.subdomain.present? ? "#{ws.subdomain}.#{ApplicationController::PLATFORM_HOST}" : ApplicationController::PLATFORM_HOST
    "https://#{host}/merchant/billing"
  end
end
