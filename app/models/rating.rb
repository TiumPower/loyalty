class Rating < ApplicationRecord
  acts_as_tenant(:workspace)

  belongs_to :workspace
  belongs_to :member
  belongs_to :outlet, optional: true
  belongs_to :replied_by, class_name: "User", optional: true

  # Fixed vocabulary so the shop page can count them; free text stays in
  # `comment`. Labels live in the locale files, keyed by these slugs.
  TAGS = %w[great_taste fast_service cozy_space friendly_staff good_value clean_space].freeze

  # Only ever store keys we know about — the chips post arbitrary strings.
  def tag_list = Array(tags).map(&:to_s) & TAGS

  validates :stars, inclusion: { in: 1..5 }

  scope :recent,     -> { order(created_at: :desc) }
  scope :unanswered, -> { where(replied_at: nil) }
  scope :low,        -> { where("stars <= 3") }

  def replied? = replied_at.present?
  def low?     = stars <= 3
end
