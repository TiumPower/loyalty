class LoyaltyProgram < ApplicationRecord
  acts_as_tenant(:workspace)

  SCAN_MODES = %w[staff_scans_member member_scans_pos both].freeze

  belongs_to :workspace

  # Upper bounds keep the int4 columns from overflowing on the way to Postgres
  # (a typo used to come back as a 500), and keep a fat-fingered rate from
  # quietly paying out thousands of points a bill.
  MAX_EARN_POINTS = 100_000
  MAX_EARN_PER    = 1_000_000_000
  MAX_MONTHS      = 120 # 10 years, for both the tier cycle and points expiry

  validates :scan_mode, inclusion: { in: SCAN_MODES }
  validates :earn_points,
            numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_EARN_POINTS }
  validates :earn_per_amount,
            numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_EARN_PER }
  # A cycle of 0 made cycle_points count only what was created this instant, so
  # saving the form dropped every customer in the shop to the bottom tier. The
  # field had no minimum, so it was one keystroke away.
  validates :tier_cycle_months,
            numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_MONTHS }
  validates :points_expiry_months,
            numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: MAX_MONTHS }
  validates :currency, format: { with: /\A[A-Z]{3}\z/, message: :not_a_currency_code }

  normalizes :currency, with: ->(c) { c.to_s.strip.upcase }

  # Legacy rows may hold 0; never let that mean "this instant".
  DEFAULT_CYCLE_MONTHS = 12
  def cycle_months
    m = tier_cycle_months.to_i
    m.positive? ? m : DEFAULT_CYCLE_MONTHS
  end

  # Points earned for a purchase of `amount` (currency units), before tier multiplier.
  def points_for(amount)
    return 0 unless points_enabled && earn_per_amount.to_i.positive?
    (amount.to_f / earn_per_amount * earn_points).floor
  end

  def points_expire? = points_expiry_months.to_i.positive?
  # When points earned now would lapse (nil = never).
  def points_expire_at(from = Time.current) = points_expire? ? from + points_expiry_months.months : nil

  # Counter earning is staff-scans-member only. The customer-self-scan-POS mode
  # was removed (confusing vs the check-in QR), so scan_member? is always off
  # regardless of any legacy stored scan_mode value.
  def scan_staff?  = true
  def scan_member? = false

  def earn_rate_label
    amt = "#{ActiveSupport::NumberHelper.number_to_delimited(earn_per_amount)}#{currency == 'VND' ? 'đ' : ' ' + currency}"
    I18n.t("customer.earn_rate", pts: earn_points, amt: amt)
  end
end
