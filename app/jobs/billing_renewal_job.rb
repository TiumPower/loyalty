# Daily billing cron:
#  1. For auto-renew shops within 5 days of expiry, pre-generate the next
#     (calendar-month) invoice + PayOS link and email the owner a pay reminder.
#  2. Auto-suspend shops that are more than GRACE_DAYS past due (email the owner);
#     paying reopens them (see Invoice#apply_payment! + Workspace#auto_suspended?).
#
# PayOS one-time links can't auto-charge, so this generates + reminds rather
# than charging.
class BillingRenewalJob < ApplicationJob
  queue_as :default

  def perform
    service = PayosService.new
    ActsAsTenant.without_tenant do
      Workspace.find_each do |ws|
        ActsAsTenant.with_tenant(ws) do
          ensure_upcoming_invoice(ws, service) if ws.auto_renew && ws.status == "active"
          auto_suspend_if_overdue(ws)
        end
      end
    end
  end

  private

  def ensure_upcoming_invoice(ws, service)
    # Only after the current period has actually ended — never pre-generate a
    # future month's invoice.
    return unless ws.paid_until && ws.paid_until <= Time.current
    start_d, end_d = ws.next_billing_period
    return if ws.invoices.pending.exists?(period_start: start_d)

    invoice = ws.invoices.create!(plan: ws.plan, amount: ws.plan_record.price,
                                  period_start: start_d, period_end: end_d, status: "pending")
    attach_payos_link(invoice, ws, service)
    BillingMailer.invoice_ready(invoice).deliver_later if ws.billing_email.present?
    Rails.logger.info("[BillingRenewal] invoice ##{invoice.id} for #{ws.subdomain}")
  rescue => e
    Rails.logger.error("[BillingRenewal] #{ws.subdomain}: #{e.class} #{e.message}")
  end

  def attach_payos_link(invoice, ws, service)
    return unless service.configured?
    data = service.create_payment_link(
      order_code:  invoice.payos_order_code,
      amount:      invoice.amount,
      description: "Loyalty #{ws.plan}",
      return_url:  Rails.application.routes.url_helpers.merchant_billing_return_url(
                     code: invoice.payos_order_code, host: "loyalty.tiumpower.com", protocol: "https"),
      cancel_url:  "https://loyalty.tiumpower.com/merchant/billing"
    )
    invoice.update!(checkout_url: data["checkoutUrl"]) if data && data["checkoutUrl"]
  rescue => e
    Rails.logger.error("[BillingRenewal] PayOS link #{ws.subdomain}: #{e.class} #{e.message}")
  end

  def auto_suspend_if_overdue(ws)
    return unless %w[active past_due trial].include?(ws.status)
    d = ws.subscription_overdue_days
    return unless d && d > Workspace::GRACE_DAYS

    ws.auto_suspend_for_nonpayment!
    BillingMailer.suspended(ws).deliver_later if ws.billing_email.present?
    Rails.logger.info("[BillingRenewal] auto-suspended #{ws.subdomain} (#{d}d overdue)")
  rescue => e
    Rails.logger.error("[BillingRenewal] suspend #{ws.subdomain}: #{e.class} #{e.message}")
  end
end
