class PointTransaction < ApplicationRecord
  acts_as_tenant(:workspace)

  KINDS = %w[earn redeem adjust expire referral mission game birthday void].freeze
  # Kinds that build tier standing when positive. A "void" is the mirror of an
  # "earn", so it must also pull cycle points back down — hence the OR below.
  TIER_KINDS = %w[earn referral mission game birthday adjust].freeze

  belongs_to :workspace
  belongs_to :member
  belongs_to :outlet, optional: true
  belongs_to :staff, class_name: "User", optional: true
  belongs_to :source, polymorphic: true, optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :amount, numericality: { other_than: 0 }

  # A purchase writes several rows in the same instant. Ordered on created_at
  # alone, Postgres may return ties in any order, so an offset-paginated ledger
  # could show one row on two pages and never show another.
  scope :recent, -> { order(created_at: :desc, id: :desc) }
  scope :credits, -> { where("amount > 0") }
  scope :debits,  -> { where("amount < 0") }
  # Reporting scopes. A "void" row is a negative mirror of an earn, so it must be
  # netted off what was ISSUED — not counted as points the customer redeemed
  # (that would inflate "điểm đã đổi" and the redemption rate).
  scope :net_credits, -> { where("amount > 0 OR kind = 'void'") }
  # "expire" is the same trap from the other side: points that lapsed unused are
  # the OPPOSITE of redeemed. Counting them here told a merchant running a 6-month
  # expiry window that customers were redeeming heavily when in fact the points
  # were quietly dying — the one number they would change the programme over.
  # They are still a real drain on the liability, so report them separately.
  scope :redemptions, -> { debits.where.not(kind: %w[void expire]) }
  scope :expirations, -> { where(kind: "expire") }
  # Points that count toward tier standing (earned, not spent) — minus anything
  # reversed by a voided bill.
  scope :tier_qualifying, -> { where("(kind IN (?) AND amount > 0) OR kind = 'void'", TIER_KINDS) }

  def credit? = amount.positive?

  ICONS = {
    "earn" => "☕", "redeem" => "🎁", "referral" => "🤝", "mission" => "✅",
    "game" => "🎡", "birthday" => "🎂", "adjust" => "⚙", "expire" => "⌛",
    "void" => "↩️"
  }.freeze
  def icon = ICONS[kind] || "•"

  def title
    return note if note.present? && %w[adjust void].include?(kind)
    I18n.t("customer.tx.#{kind}", default: I18n.t("customer.tx.adjust"))
  end
end
