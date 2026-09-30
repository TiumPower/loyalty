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
  validates :gradient_from, :gradient_to, :pill_bg, :pill_fg, :pill_border,
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

  # ---- The badge pill -----------------------------------------------------
  #
  # The design draws a tier badge as a soft tinted pill with coloured lettering,
  # not as the saturated gradient the hexagon crest uses. Shops that have not
  # been given the design's palette fall back to their gradient: a light tint of
  # it behind, the deep stop in front.
  def pill_background
    return pill_bg if self.class.hex?(pill_bg)
    from = self.class.hex?(gradient_from) ? gradient_from : "#B08D57"
    "color-mix(in srgb, #{from} 16%, #FFFFFF)"
  end

  def pill_foreground
    return pill_fg if self.class.hex?(pill_fg)
    self.class.hex?(gradient_to) ? gradient_to : "#7A5C3A"
  end

  def pill_ring = self.class.hex?(pill_border) ? pill_border : nil

  # Lettering that stays readable on this tier's own gradient.
  #
  # Every badge used to print white, which is fine on a deep bronze and
  # unreadable on a pale gold — and the merchant picks these colours, so pale
  # ones will happen. The design's own gold crest letters GOLD in dark ink for
  # exactly this reason. Pick whichever of white/ink actually contrasts better,
  # with a bias to white: on a mid-tone the two are within a few percent of each
  # other and white is what a badge is expected to look like.
  INK = "#2E241B".freeze
  DARK_INK_ADVANTAGE = 1.25

  def ink_color
    colors = [gradient_from, gradient_to].select { |c| self.class.hex?(c) }
    return "#FFFFFF" if colors.empty?
    l = colors.sum { |c| self.class.luminance(c) } / colors.size
    on_white = 1.05 / (l + 0.05)
    on_ink   = (l + 0.05) / (self.class.luminance(INK) + 0.05)
    on_ink > on_white * DARK_INK_ADVANTAGE ? INK : "#FFFFFF"
  end

  # WCAG relative luminance, so the choice above is measured rather than eyeballed.
  def self.luminance(hex)
    h = hex.to_s.delete("#")
    h = h.chars.map { |c| c * 2 }.join if h.length == 3
    r, g, b = h.scan(/../).map { |pair| pair.to_i(16) / 255.0 }
    lin = ->(c) { c <= 0.03928 ? c / 12.92 : (((c + 0.055) / 1.055)**2.4) }
    (0.2126 * lin.call(r)) + (0.7152 * lin.call(g)) + (0.0722 * lin.call(b))
  end

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
