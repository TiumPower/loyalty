class Tier < ApplicationRecord
  acts_as_tenant(:workspace)

  belongs_to :workspace

  # gradient_css is interpolated straight into style="background:…" on the
  # customer PWA, so anything that isn't a colour injects CSS — including a
  # url() that fires a request from the customer's browser. Same rule the
  # workspace theme colours use.
  HEX_COLOR_RE = /\A#(?:\h{3}|\h{6})\z/

  # Ceilings that keep the columns (numeric(4,2), int4) from overflowing on the
  # way to Postgres: without them a typo came back as a 500 instead of a field
  # error. A 20× multiplier or a 10-triệu-point top tier is already far past
  # anything a real programme uses.
  MAX_MULTIPLIER  = 20
  MAX_THRESHOLD   = 10_000_000
  MAX_BENEFITS    = 10
  MAX_BENEFIT_LEN = 160

  validates :key, :name, presence: true
  validates :key, uniqueness: { scope: :workspace_id }
  validates :name, length: { maximum: 40 }
  validates :threshold_points,
            numericality: { only_integer: true, greater_than_or_equal_to: 0,
                            less_than_or_equal_to: MAX_THRESHOLD }
  validates :multiplier,
            numericality: { greater_than_or_equal_to: 1, less_than_or_equal_to: MAX_MULTIPLIER }
  validates :gradient_from, :gradient_to,
            format: { with: HEX_COLOR_RE, message: :not_a_hex_color }, allow_blank: true
  validate  :benefits_are_a_short_list

  scope :ordered, -> { order(:position) }

  def gradient_css
    from = self.class.hex?(gradient_from) ? gradient_from : "#B08D57"
    to   = self.class.hex?(gradient_to)   ? gradient_to   : "#7A5C3A"
    "linear-gradient(135deg, #{from} 0%, #{to} 100%)"
  end

  # Belt and braces for rows written before the validation existed.
  def self.hex?(value) = value.to_s.match?(HEX_COLOR_RE)

  def next_tier
    workspace.tiers.ordered.select { |t| t.threshold_points > threshold_points }
             .min_by { |t| [t.threshold_points, t.position] }
  end

  private

  def benefits_are_a_short_list
    list = benefits
    return if list.blank?
    return errors.add(:benefits, :invalid) unless list.is_a?(Array)
    errors.add(:benefits, :too_many, count: MAX_BENEFITS) if list.size > MAX_BENEFITS
    errors.add(:benefits, :too_long, count: MAX_BENEFIT_LEN) if list.any? { |b| b.to_s.length > MAX_BENEFIT_LEN }
  end
end
