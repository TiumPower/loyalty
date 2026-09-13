class Reward < ApplicationRecord
  acts_as_tenant(:workspace)

  KINDS = %w[voucher gift discount].freeze
  VALUE_UNITS = %w[vnd percent item].freeze

  belongs_to :workspace
  # Refuse deletion while the reward is in use — deleting it would wipe issued
  # vouchers from customers' wallets or break a stamp card / campaign. Merchants
  # deactivate (active: false) instead. destroy returns false + adds an error.
  has_many :vouchers,     dependent: :restrict_with_error
  has_many :stamp_cards,  dependent: :restrict_with_error
  has_many :campaigns,    dependent: :restrict_with_error
  has_many :promo_codes,  dependent: :restrict_with_error

  def in_use? = vouchers.exists? || stamp_cards.exists? || campaigns.exists? || promo_codes.exists?

  # Gifts/items don't need a numeric value → default a blank one to 0 so it
  # never hits the NOT NULL column. For voucher/discount a blank value fails
  # the presence check below (clear form error) instead of 500-ing.
  before_validation { self.value = 0 if value.blank? && (kind == "gift" || value_unit == "item") }

  validates :title, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :value_unit, inclusion: { in: VALUE_UNITS }
  validates :value, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :value, numericality: { less_than_or_equal_to: 100 },
                    if: -> { value_unit == "percent" && value.present? }

  scope :active,   -> { where(active: true) }
  scope :listed,   -> { where(archived_at: nil) } # hide archived (soft-deleted) rewards
  scope :ordered,  -> { order(:position, :id) }
  def archived? = archived_at.present?
  # Rewards a member can redeem with points right now.
  scope :redeemable, -> { active.where.not(cost_points: nil) }

  def in_stock?  = stock.nil? || stock > redeemed_count

  # Claim one unit, atomically. Returns true only for the caller that got it —
  # the affected-row count is what decides the race, so two customers can never
  # both take the last unit. An unlimited reward (stock NULL) always wins.
  #
  # Every path that hands out a voucher must go through this. The spin wheel and
  # stamp cards used to write the Voucher directly, so a prize limited to "1
  # suất" was given away indefinitely and redeemed_count never moved — the
  # merchant could not even see it happening.
  def claim_stock!
    self.class.where(id: id)
        .where("stock IS NULL OR redeemed_count < stock")
        .update_all("redeemed_count = redeemed_count + 1, updated_at = NOW()")
        .positive?
  end

  # A reward is available now when: inside its date range AND (no time-windows, or
  # the current weekday+hour falls inside ANY of its windows). Merchants can add
  # several windows (different weekdays/hours) — the scanner uses this same check.
  def within_window?(now = Time.current)
    return false unless starts_at.nil? || starts_at <= now
    return false unless ends_at.nil?   || ends_at >= now
    wins = schedule_windows
    return true if wins.empty?
    wins.any? { |w| window_matches?(w, now) }
  end
  def available?(now = Time.current) = active? && in_stock? && within_window?(now)

  # Redemption state for the customer catalog. We now SHOW rewards even outside
  # their redeem window (dimmed + a notice) instead of hiding them, so a member
  # can see what's coming and only redeem while it's :open.
  #   :open → redeemable now · :upcoming → before starts_at · :closed → has
  #   recurring day/hour windows, none active right now · :ended → past ends_at
  #   · :out_of_stock → no stock left · :inactive → turned off
  def redeem_state(now = Time.current)
    return :inactive if !active?
    return :ended    if ends_at.present? && ends_at < now
    return :upcoming if starts_at.present? && starts_at > now
    return :out_of_stock unless in_stock?
    return :open if within_window?(now)
    :closed
  end

  def redeem_open?(now = Time.current) = redeem_state(now) == :open

  # Localized one-line reason the redeem button is disabled (nil when :open).
  def redeem_window_hint(now = Time.current)
    case redeem_state(now)
    when :upcoming then I18n.t("customer.reward_detail.opens_at", time: I18n.l(starts_at, format: :short))
    when :ended    then I18n.t("customer.reward_detail.ended")
    when :out_of_stock then I18n.t("customer.reward_detail.sold_out")
    when :closed   then (schedule_summary ? I18n.t("customer.reward_detail.window_only", win: schedule_summary) : I18n.t("customer.reward_detail.closed_now"))
    end
  end

  # Expiry for a voucher issued now: a fixed offer-level date if set, otherwise
  # valid_days after the claim.
  def voucher_expiry_from(now = Time.current)
    expires_at.presence || (valid_days.to_i.positive? ? valid_days.days.since(now) : 30.days.since(now))
  end

  WDAYS_VI = %w[CN T2 T3 T4 T5 T6 T7].freeze # fallback; index = wday (0=Sun)

  # Locale-aware short weekday labels (index = wday, 0=Sun). Falls back to VI.
  def self.wday_labels
    labels = I18n.t("merchant.rewards.wday_short", default: nil)
    labels.is_a?(Array) && labels.size == 7 ? labels : WDAYS_VI
  end

  # Normalised list of time-windows. Supports the legacy single-window shape
  # ({days,from_hour,to_hour}) by wrapping it as one window.
  def schedule_windows
    sch = schedule || {}
    if sch["windows"].is_a?(Array)
      sch["windows"]
    elsif sch["days"].present? || sch["from_hour"].present?
      [{ "days" => sch["days"], "from_hour" => sch["from_hour"], "to_hour" => sch["to_hour"] }]
    else
      []
    end
  end

  # Human summary of all windows (nil when always-on within the date range).
  def schedule_summary
    labels = schedule_windows.map { |w| window_label(w) }.compact
    labels.presence && labels.join(" · ")
  end

  private

  def window_matches?(w, now)
    days = Array(w["days"]).map(&:to_i)
    return false if days.present? && !days.include?(now.wday)   # 0=CN … 6=T7
    fh, th = w["from_hour"], w["to_hour"]
    return true unless fh.present? && th.present?
    (fh.to_i..th.to_i).cover?(now.hour)
  end

  def window_label(w)
    parts = []
    days = Array(w["days"]).map(&:to_i).sort
    labels = self.class.wday_labels
    parts << days.map { |d| labels[d] }.join(",") if days.present?
    parts << "#{format('%02d', w['from_hour'])}h–#{format('%02d', w['to_hour'])}h" if w["from_hour"].present? && w["to_hour"].present?
    parts.join(" ").presence
  end

  public

  def remaining
    stock.nil? ? nil : [stock - redeemed_count, 0].max
  end

  def value_label
    case value_unit
    when "percent" then "-#{value}%"
    when "item"    then I18n.t("customer.reward.free")
    else "-#{ActiveSupport::NumberHelper.number_to_delimited(value)}đ"
    end
  end

  def display_icon = icon.presence || { "voucher" => "🎟️", "gift" => "🎁", "discount" => "🏷️" }[kind]

  # The raw column value was being printed straight to the screen, so a shop
  # filtering by "Quà tặng" saw cards labelled "gift", and customers read
  # "VOUCHER"/"GIFT" on the reward ticket in an otherwise Vietnamese app.
  def kind_label = I18n.t("merchant.rewards.kind_#{kind}", default: kind.to_s.humanize)
end
