class Badge < ApplicationRecord
  acts_as_tenant(:workspace)
  # Refuses a reward that is off / sold out / ended (see the concern).
  include AssignableReward

  CRITERIA = %w[first_purchase purchases_count points_total night_owl].freeze

  belongs_to :workspace
  belongs_to :reward, optional: true # optional voucher granted when earned
  has_many :member_badges, dependent: :destroy

  validates :key, :name, presence: true
  validates :key, uniqueness: { scope: :workspace_id }

  scope :ordered, -> { order(:position, :id) }

  def display_icon = icon.presence || "🏅"

  # Localized "how to earn this badge" line for the customer app, so members
  # know what to strive for even when the merchant left the description blank.
  def requirement_text
    case criteria_type
    when "first_purchase" then I18n.t("customer.badges.req_first")
    when "purchases_count" then I18n.t("customer.badges.req_count", n: threshold)
    when "points_total"    then I18n.t("customer.badges.req_points", n: threshold)
    when "night_owl"       then I18n.t("customer.badges.req_night", n: threshold)
    else criteria_type
    end
  end

  # How far along `member` is, as [done, target]. The badge grid and the badge
  # page both show "18/25" rather than a bare lock, so the criteria have to
  # report a number, not just a yes/no.
  def progress_for(member)
    target = threshold.to_i
    case criteria_type
    when "first_purchase"
      [member.purchases.not_voided.limit(1).count, 1]
    when "purchases_count"
      [[member.purchases.not_voided.count, target].min, target]
    when "points_total"
      [[member.lifetime_points.to_i, target].min, target]
    when "night_owl"
      done = member.purchases.not_voided.where("EXTRACT(hour FROM created_at) >= ?", 22).count
      [[done, target].min, target]
    else
      [earned_by?(member) ? 1 : 0, 1]
    end
  end

  # Does `member` currently satisfy this badge?
  def earned_by?(member)
    case criteria_type
    when "first_purchase" then member.purchases.not_voided.any?
    when "purchases_count" then member.purchases.not_voided.count >= threshold
    when "points_total"    then member.lifetime_points >= threshold
    when "night_owl"       then member.purchases.not_voided.where("EXTRACT(hour FROM created_at) >= ?", 22).count >= threshold
    else false
    end
  end
end
