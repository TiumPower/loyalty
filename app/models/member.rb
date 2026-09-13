class Member < ApplicationRecord
  # End customer of a single workspace. Auth = phone + OTP (Warden session via
  # Devise; the password column is unused in dev). Tenant-scoped by workspace.
  acts_as_tenant(:workspace)

  # The merchant logo has had a type and size limit for a while; this upload had
  # none at all — and it is shown to other customers on the shop's reviews page.
  AVATAR_TYPES = %w[image/png image/jpeg image/webp image/gif].freeze
  AVATAR_MAX_BYTES = 3.megabytes

  has_one_attached :avatar

  devise :database_authenticatable, :rememberable, :trackable

  LOCALES = %w[vi en].freeze
  # Acquisition channels, in the order the dashboard lists them. "direct" is the
  # catch-all for someone who simply opened the shop's link.
  JOIN_SOURCES = %w[referral campaign checkin pos direct].freeze
  JOIN_SOURCE_ICONS = {
    "referral" => "🤝", "campaign" => "🎯", "checkin" => "📍",
    "pos" => "🧾", "direct" => "🚶"
  }.freeze

  def join_source_key = JOIN_SOURCES.include?(join_source) ? join_source : "direct"
  def self.join_source_label(key) = I18n.t("merchant.join_sources.#{key}", default: key.to_s.humanize)
  def self.join_source_icon(key)  = JOIN_SOURCE_ICONS[key] || "🚶"

  belongs_to :workspace
  belongs_to :referred_by, class_name: "Member", optional: true
  has_many :referrals, class_name: "Member", foreign_key: :referred_by_id, dependent: :nullify
  has_many :point_transactions, dependent: :destroy
  has_many :purchases, dependent: :destroy
  has_many :vouchers, dependent: :destroy
  has_many :promo_claims, dependent: :destroy
  has_many :stamp_card_memberships, dependent: :destroy
  has_many :mission_progresses, dependent: :destroy
  has_many :member_badges, dependent: :destroy
  has_many :badges, through: :member_badges
  has_many :spin_logs, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :push_subscriptions, dependent: :destroy
  has_many :referrals_made, class_name: "Referral", foreign_key: :referrer_id, dependent: :destroy
  has_one  :referral_received, class_name: "Referral", foreign_key: :referred_id, dependent: :destroy

  # Login identifier is email (OTP). Phone is now an optional profile field.
  validates :email, uniqueness: { scope: :workspace_id, case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP, message: "email không hợp lệ" },
                    allow_blank: true
  validates :phone, uniqueness: { scope: :workspace_id },
                    format: { with: /\A0\d{8,10}\z/, message: "số điện thoại không hợp lệ" },
                    allow_blank: true
  validates :locale, inclusion: { in: LOCALES }
  validate :avatar_is_a_reasonable_image
  validate :birthday_is_plausible

  # Oldest birthday we will accept. Anything outside this is a typo, and a
  # birthday in the future silently opts the member out of the birthday gift.
  OLDEST_BIRTHDAY = 120.years

  before_validation :normalize_phone, :normalize_email
  before_create :assign_referral_code, :set_placeholder_password

  # Current tier from the cached key (falls back to lowest tier).
  def tier
    ordered_tiers.detect { |t| t.key == tier_key } || ordered_tiers.first
  end

  def ordered_tiers
    @ordered_tiers ||= workspace.tiers.ordered.to_a
  end

  # Points accumulated within the current tier cycle (drives tier standing;
  # not reduced by redemptions).
  def cycle_points
    since = workspace.program.cycle_months.months.ago
    point_transactions.tier_qualifying.where("created_at >= ?", since).sum(:amount)
  end

  # The tier a given cycle-point total qualifies for. Picked by threshold rather
  # than by position: these used to assume thresholds climb with position, so a
  # workspace whose rungs were out of order (nothing stopped that) put customers
  # on the wrong tier and told them the wrong next rung.
  def tier_for(points)
    ordered_tiers.select { |t| t.threshold_points <= points }
                 .max_by { |t| [t.threshold_points, t.position] } || ordered_tiers.first
  end

  def next_tier
    ordered_tiers.select { |t| t.threshold_points > (tier&.threshold_points || 0) }
                 .min_by { |t| [t.threshold_points, t.position] }
  end

  def points_to_next
    nt = next_tier
    nt ? [nt.threshold_points - cycle_points, 0].max : 0
  end

  def tier_progress_pct
    nt = next_tier
    return 100 unless nt
    lo = tier&.threshold_points.to_i
    span = nt.threshold_points - lo
    return 100 if span <= 0
    (((cycle_points - lo).to_f / span) * 100).clamp(0, 100).round
  end

  # Recompute cached balance / lifetime / tier from the ledger. Call after any
  # point movement.
  def recompute_points!
    self.points_balance  = point_transactions.sum(:amount)
    # Lifetime = everything ever credited, less anything a voided bill took back
    # (a "void" row is negative, so summing it in is the reversal).
    self.lifetime_points = point_transactions.where("amount > 0 OR kind = 'void'").sum(:amount)
    self.tier_key        = tier_for(cycle_points)&.key
    save!(validate: false)
  end

  # FIFO points expiry: debits (redeem/expire) consume the oldest credit lots
  # first; a lot with an expires_at in the past that hasn't been consumed is
  # expirable. Idempotent (previous expire debits are counted as consumption).
  def expirable_points(now: Time.current)
    total = 0
    each_unconsumed_lot { |left, exp| total += left if exp && exp <= now }
    total
  end

  # [amount, nearest_date] of unconsumed points expiring within `within`.
  def points_expiring_soon(within: 30.days, now: Time.current)
    amt = 0; date = nil
    each_unconsumed_lot do |left, exp|
      next unless exp && exp > now && exp <= now + within
      amt += left
      date = exp if date.nil? || exp < date
    end
    [amt, date]
  end

  # Yields [unconsumed_amount, expires_at] for each credit lot, oldest first,
  # after applying all debits FIFO.
  def each_unconsumed_lot
    remaining_debit = point_transactions.debits.sum(:amount).abs
    point_transactions.credits.order(:created_at).pluck(:amount, :expires_at).each do |amount, exp|
      consume = [amount, remaining_debit].min
      remaining_debit -= consume
      left = amount - consume
      yield(left, exp) if left.positive?
    end
  end

  def display_name
    name.presence || "Thành viên"
  end

  def initials
    display_name.split.map { |w| w[0] }.first(2).join.upcase
  end

  # Contact line for screens the customer holds up to a stranger — the QR code
  # they show a cashier, the membership card. Enough to tell two members apart,
  # not enough to read someone's address off their phone across the counter.
  def masked_contact
    if email.present?
      user, _, domain = email.partition("@")
      head = user[0, 2]
      "#{head}#{'•' * [user.length - 2, 1].max}@#{domain}"
    elsif phone.present?
      "#{phone[0, 3]}#{'•' * [phone.length - 5, 1].max}#{phone[-2, 2]}"
    end
  end

  private

  def avatar_is_a_reasonable_image
    return unless avatar.attached?
    blob = avatar.blob
    return if blob.nil?
    unless AVATAR_TYPES.include?(blob.content_type)
      errors.add(:avatar, "phải là ảnh PNG, JPG, WEBP hoặc GIF")
    end
    if blob.byte_size.to_i > AVATAR_MAX_BYTES
      errors.add(:avatar, "tối đa #{(AVATAR_MAX_BYTES / 1.megabyte).to_i}MB")
    end
  end

  def birthday_is_plausible
    return if birthday.blank?
    if birthday > Date.current
      errors.add(:birthday, "không thể ở tương lai")
    elsif birthday < OLDEST_BIRTHDAY.ago.to_date
      errors.add(:birthday, "không hợp lệ")
    end
  end

  def normalize_phone
    self.phone = phone.to_s.gsub(/\s+/, "").presence
  end

  def normalize_email
    self.email = self.class.canonical_email(email)
  end

  # Canonicalize so alias tricks map to one account: strip a "+tag" (all
  # providers) and, for Gmail, ignore dots and treat googlemail as gmail.
  # e.g. quocvietlee+1@gmail.com and quoc.vietlee@gmail.com → quocvietlee@gmail.com
  def self.canonical_email(raw)
    e = raw.to_s.strip.downcase
    return nil if e.blank?
    return e unless e.include?("@")
    local, domain = e.split("@", 2)
    local = local.split("+", 2).first.to_s
    if %w[gmail.com googlemail.com].include?(domain)
      local  = local.delete(".")
      domain = "gmail.com"
    end
    local.present? ? "#{local}@#{domain}" : e
  end

  def assign_referral_code
    return if referral_code.present?
    loop do
      code = "#{workspace&.subdomain.to_s[0, 3].upcase}#{SecureRandom.alphanumeric(4).upcase}"
      unless Member.unscoped.exists?(workspace_id: workspace_id, referral_code: code)
        self.referral_code = code
        break
      end
    end
  end

  def set_placeholder_password
    self.password = SecureRandom.hex(16) if encrypted_password.blank?
  end
end
