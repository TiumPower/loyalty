class Workspace < ApplicationRecord
  extend FriendlyId
  friendly_id :name, use: :slugged

  INDUSTRIES = %w[fnb retail service].freeze
  STATUSES   = %w[pending trial active past_due suspended].freeze
  STATUS_LABELS = {
    "pending" => "Chờ duyệt", "trial" => "Dùng thử", "active" => "Đang hoạt động",
    "past_due" => "Quá hạn", "suspended" => "Tạm ngưng"
  }.freeze
  PLAN_PRICES = { "starter" => 199_000, "growth" => 499_000, "scale" => 1_290_000 }.freeze
  PLANS      = %w[starter growth scale].freeze

  has_one_attached :logo
  has_many :memberships, dependent: :destroy
  has_many :users,   through: :memberships
  has_many :outlets, dependent: :destroy
  has_many :members, dependent: :destroy
  has_many :tiers, -> { order(:position) }, dependent: :destroy
  has_many :rewards, dependent: :destroy
  has_many :campaigns, dependent: :destroy
  has_many :promo_codes, dependent: :destroy
  has_many :pos_charges, dependent: :destroy
  has_many :stamp_cards, dependent: :destroy
  has_many :missions, dependent: :destroy
  has_many :badges, dependent: :destroy
  has_one  :spin_wheel, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :broadcasts, dependent: :destroy
  has_many :referrals, dependent: :destroy
  has_many :ratings, dependent: :destroy
  has_many :invoices, dependent: :destroy
  has_one  :loyalty_program, dependent: :destroy
  has_many :workspace_insights, dependent: :destroy
  has_many :merchant_alerts, dependent: :destroy

  validates :name, :subdomain, presence: true
  validates :subdomain, uniqueness: true, format: { with: /\A[a-z0-9][a-z0-9-]*\z/ }
  validates :industry, inclusion: { in: INDUSTRIES }
  validates :status,   inclusion: { in: STATUSES }

  before_validation :default_subdomain, on: :create

  # -- Program helpers -----------------------------------------------------
  def program
    loyalty_program || build_loyalty_program
  end

  def default_locale_sym
    %w[vi en].include?(locale_default) ? locale_default.to_sym : :vi
  end

  def active?  = status == "active"
  def trial?   = status == "trial"

  TRIAL_DAYS = 14 # self-serve signups get a working trial, no manual approval

  # Start (or restart) a free trial: a real clock via paid_until so the whole
  # billing lifecycle (expiry warning, invoice, grace, auto-suspend) just works.
  def start_trial!(days = TRIAL_DAYS)
    update!(status: "trial", paid_until: days.days.from_now)
  end

  # Every shop must have at least one branch (the check-in QR lives on branches).
  # Auto-create one from the shop's own info; the owner edits it later.
  def ensure_default_outlet!
    ActsAsTenant.with_tenant(self) do
      return outlets.first if outlets.exists?
      outlets.create!(code: "MAIN", name: name.presence || "Chi nhánh chính",
                      address: branding_value("address").presence, active: true)
    end
  end
  def pending? = status == "pending"
  def onboarded? = settings["onboarded"] == true

  # Version tag baked into the check-in QR token. Rotating it invalidates every
  # previously printed poster (so a leaked QR can be revoked). Lazily initialised.
  def checkin_nonce
    settings["checkin_nonce"].presence || rotate_checkin_nonce!
  end

  def rotate_checkin_nonce!
    nonce = SecureRandom.hex(8)
    update!(settings: settings.merge("checkin_nonce" => nonce))
    nonce
  end
  def status_label = STATUS_LABELS[status]

  # Single source of truth for "đã trả / đang nợ / dùng thử" across super admin.
  #   :paid      — active paid subscription (paid_until in the future)
  #   :trial     — free trial still running
  #   :owing     — clock lapsed & not active → owes money (incl. auto-suspended
  #                for non-payment, and lapsed trials that must convert)
  #   :suspended — operator suspend (not payment-related)
  #   :new       — no billing clock yet
  def payment_state
    return :suspended if status == "suspended" && !auto_suspended?
    return :trial     if trial? && subscription_active?
    return :paid      if subscription_active?
    return :owing     if paid_until.present?
    :new
  end

  PAYMENT_STATES = %i[paid trial owing suspended new].freeze
  PAYMENT_LABELS = {
    paid: "Đã thanh toán", trial: "Dùng thử", owing: "Đang nợ",
    suspended: "Tạm ngưng", new: "Chưa có kỳ"
  }.freeze
  def payment_label = PAYMENT_LABELS[payment_state]

  # ---- Plan (limits & feature gates) ------------------------------------
  def plan_record
    @plan_record ||= Plan.for(plan)
  end

  def monthly_price = active? ? plan_record.price.to_i : 0

  # During the free trial the shop gets FULL access — every feature unlocked and
  # no caps — so they can evaluate everything; they pick a plan when they pay.
  def full_access? = trial?

  def plan_allows?(feature)
    return true if full_access?
    case feature.to_sym
    when :stamps        then plan_record.allow_stamps
    when :gamification  then plan_record.allow_gamification
    when :campaigns     then plan_record.allow_campaigns
    when :custom_domain then plan_record.allow_custom_domain
    when :ab_testing    then plan_record.allow_ab_testing
    else true
    end
  end

  def outlet_limit = full_access? ? nil : plan_record.max_outlets
  def member_limit = full_access? ? nil : plan_record.max_members

  # ---- Subscription / billing -------------------------------------------
  GRACE_DAYS = 10 # days after expiry before an unpaid workspace is locked out

  def subscription_active? = paid_until.present? && paid_until >= Time.current

  def subscription_days_left
    return nil if paid_until.nil?
    ((paid_until - Time.current) / 1.day).ceil
  end

  # Whole days the subscription is past due (nil if never paid or still active).
  def subscription_overdue_days
    return nil if paid_until.nil? || subscription_active?
    ((Time.current - paid_until) / 1.day).floor
  end

  # Why the workspace is locked out (nil = usable):
  #   :suspended — an operator suspended it → contact support to reopen
  #   :unpaid    — subscription expired more than GRACE_DAYS ago → pay to reopen
  def access_blocked_reason
    if status == "suspended"
      # A shop auto-suspended for non-payment can reopen by paying (":unpaid" →
      # billing stays reachable); an operator suspend needs support.
      return auto_suspended? ? :unpaid : :suspended
    end
    d = subscription_overdue_days
    return :unpaid if d && d > GRACE_DAYS
    nil
  end

  # The billing owner (falls back to any linked user) + their email.
  def owner = memberships.find_by(role: "owner")&.user || users.first
  def billing_email = owner&.email

  # Auto-suspend bookkeeping (kept in settings so no migration is needed).
  def auto_suspended? = status == "suspended" && settings["auto_suspended"] == true

  # Flip an unpaid, past-grace shop to "suspended" (Tạm ngưng). Flagged so a
  # later payment can reopen it (unlike an operator suspend).
  def auto_suspend_for_nonpayment!
    update!(status: "suspended", settings: settings.merge("auto_suspended" => true))
  end

  # Whether the public customer-facing feedback wall is shown (default on).
  def feedback_public? = settings.fetch("feedback_public", true) != false

  # Public review page (Google Maps / Facebook). When set, a customer who rates
  # the shop highly is invited to post that review publicly too.
  def google_review_url = settings["google_review_url"].presence

  # Automation config lives in settings["automations"][kind] = {enabled, reward_id, ...}
  def automation(kind) = settings.fetch("automations", {}).fetch(kind.to_s, {})

  def access_blocked? = access_blocked_reason.present?

  # The next unpaid billing month (starts when the current paid period ends).
  # Calendar-month billing: every period runs from the 1st to the last day of a
  # month. An active plan renews into the next full month; an expired plan is
  # billed for the current calendar month.
  def next_billing_period
    if subscription_active?
      d = paid_until.to_date + 1.day
      start = (d.day == 1) ? d : (d.beginning_of_month + 1.month)
    else
      start = Date.current.beginning_of_month
    end
    [start, start.end_of_month]
  end

  # The FIRST period a converting trial pays for: the remainder of the month in
  # which the trial ends (prorated). Non-trial shops just get next_billing_period.
  def first_billing_period
    return next_billing_period unless trial? && paid_until.present?
    start = paid_until.to_date + 1.day
    [start, start.end_of_month]
  end

  # Amount due for a period given a plan price. A converting trial pays a
  # day-prorated share of the partial first month (rounded to 1.000đ); everyone
  # else pays the full plan price.
  def prorated_amount(price, period = first_billing_period)
    price = price.to_i
    return price unless trial?
    s, e = period
    covered = (e - s).to_i + 1
    days_in_month = e.day
    return price if covered >= days_in_month
    ((price * covered) / days_in_month.to_f / 1000).round * 1000
  end

  def can_add_outlet?(current = outlets.count)
    outlet_limit.nil? || current < outlet_limit
  end

  def can_add_member?(current = nil)
    return true if member_limit.nil?
    current ||= ActsAsTenant.with_tenant(self) { members.count }
    current < member_limit
  end

  # -- Theming (per-workspace white-label) ---------------------------------
  # Neutral defaults = the "Cozy Cafe" preset from the product mockup. Each
  # workspace overrides a handful of base tokens; the rest derive via CSS
  # color-mix in the token stylesheet + the _theme_vars partial.
  DEFAULT_THEME = {
    "primary"      => "#8C4A2F",  # warm brown
    "primary_2"    => "#E08A3C",  # orange accent
    "on_primary"   => "#FFF7EE",
    "surface"      => "#FBF6EF",  # cream
    "surface_2"    => "#F3E9DD",
    "ink"          => "#3A2A20",
    "ink_2"        => "#7A6656",
    "line"         => "#E7D9C9",
    "radius"       => "22px",
    "font_display" => "Fraunces",          # serif for big numerals
    "font_body"    => "Plus Jakarta Sans"
  }.freeze

  FONT_STACKS = {
    "Fraunces"           => '"Fraunces", Georgia, "Times New Roman", serif',
    "Playfair Display"   => '"Playfair Display", Georgia, serif',
    "Plus Jakarta Sans"  => '"Plus Jakarta Sans", ui-sans-serif, system-ui, sans-serif',
    "Inter"              => '"Inter", ui-sans-serif, system-ui, sans-serif',
    "Be Vietnam Pro"     => '"Be Vietnam Pro", ui-sans-serif, system-ui, sans-serif'
  }.freeze

  def theme_value(key)
    theme.presence&.dig(key.to_s).presence || DEFAULT_THEME[key.to_s]
  end

  # Radius as valid CSS: the appearance slider stores a bare number (e.g. "16"),
  # which is invalid for border-radius without a unit — append px.
  def css_radius
    r = theme_value(:radius).to_s.strip
    r.match?(/\A\d+(\.\d+)?\z/) ? "#{r}px" : (r.presence || "16px")
  end

  def resolved_theme
    DEFAULT_THEME.merge(theme.presence || {})
  end

  def font_stack(key)
    FONT_STACKS[theme_value(key)] || FONT_STACKS[DEFAULT_THEME[key]]
  end

  # -- Branding ------------------------------------------------------------
  DEFAULT_BRANDING = {
    "logo_text"     => nil,        # falls back to name initials
    "tagline"       => "Chương trình tri ân khách hàng",
    "customer_term" => "bạn",      # tone of voice: "bạn" / "quý khách" / "Fan cứng"
    "tone"          => "friendly"  # friendly / formal / youthful
  }.freeze

  def branding_value(key)
    branding.presence&.dig(key.to_s).presence || DEFAULT_BRANDING[key.to_s]
  end

  def logo_initials
    (branding_value("logo_text") || name).to_s.split.map { |w| w[0] }.first(2).join.upcase
  end

  private

  # A shop owner's natural instinct is to type their shop's name here, which the
  # format validation then rejected as "không hợp lệ" — even though the same
  # slugify already ran for a BLANK field. Normalise whatever they typed the
  # same way, so "Mộc Cà Phê" becomes "moccaphe" instead of an error.
  def default_subdomain
    typed = subdomain.to_s.strip
    self.subdomain =
      if typed.present?
        normalize_subdomain(typed)
      else
        slug.presence || normalize_subdomain(name.to_s)
      end
  end

  def normalize_subdomain(raw)
    I18n.transliterate(raw.to_s).downcase
        .gsub(/[^a-z0-9-]+/, "")   # spaces and punctuation simply go
        .gsub(/-+/, "-")
        .sub(/\A-+/, "")          # must start with a letter or digit
        .sub(/-+\z/, "")
  end
end
