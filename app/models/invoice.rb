class Invoice < ApplicationRecord
  acts_as_tenant(:workspace)

  STATUSES = %w[pending paid failed cancelled].freeze

  belongs_to :workspace

  validates :status, inclusion: { in: STATUSES }
  validates :amount, numericality: { greater_than_or_equal_to: 0 }

  scope :recent,  -> { order(created_at: :desc) }
  scope :pending, -> { where(status: "pending") }
  scope :paid,    -> { where(status: "paid") }

  before_create :assign_order_code

  def paid?    = status == "paid"
  def pending? = status == "pending"

  def period_label
    "#{I18n.l(period_start, format: '%d/%m/%Y')} – #{I18n.l(period_end, format: '%d/%m/%Y')}"
  end

  # Apply a successful payment: mark paid + extend the workspace subscription.
  def apply_payment!(gateway_response: {})
    # Row lock + re-check makes this idempotent under concurrent webhook/return
    # calls (PayOS retries): the second caller blocks, then sees paid? and bails.
    with_lock do
      return if paid?
      update!(status: "paid", paid_at: Time.current, gateway_response: gateway_response)
      base = [ workspace.paid_until, Time.current ].compact.max
      # Paying reopens a shop unless an operator deliberately suspended it (a
      # non-payment auto-suspend is cleared here).
      keep_suspended = workspace.status == "suspended" && !workspace.auto_suspended?
      # The plan switch only lands now, on a successful payment — cancelling a
      # checkout never changes the workspace's plan.
      workspace.update!(paid_until: [ base, period_end.end_of_day ].max,
                        status: keep_suspended ? "suspended" : "active",
                        plan: plan,
                        settings: workspace.settings.merge("auto_suspended" => false))
    end
  end

  def mark_failed!(gateway_response: {})
    update!(status: "failed", gateway_response: gateway_response) if pending?
  end

  # Issue a brand-new PayOS order code before (re)starting a checkout, so a
  # previously cancelled/expired link on this invoice can't collide at PayOS
  # ("đơn hàng đã được xử lý"). Clears the stale checkout URL too.
  def reassign_order_code!
    update!(payos_order_code: 71_000_000_000 + (Time.now.to_i % 1_000_000_000) + rand(0..999),
            checkout_url: nil)
  end

  private

  # Unique integer order code for PayOS (offset to avoid clashing with other apps
  # sharing the same PayOS merchant account).
  def assign_order_code
    self.payos_order_code ||= 71_000_000_000 + (Time.now.to_i % 1_000_000_000)
  end
end
