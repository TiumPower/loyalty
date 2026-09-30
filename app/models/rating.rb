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

  # Photos of the visit, as in the design ("Add visit photos · up to 4").
  # They go on the public shop page, so the limits are enforced here rather than
  # trusted from the form.
  PHOTO_TYPES     = %w[image/png image/jpeg image/webp image/heic image/heif].freeze
  PHOTO_MAX_BYTES = 8.megabytes
  MAX_PHOTOS      = 4

  has_many_attached :photos
  validate :photos_are_reasonable

  validates :stars, inclusion: { in: 1..5 }

  scope :recent,     -> { order(created_at: :desc) }
  scope :unanswered, -> { where(replied_at: nil) }
  scope :low,        -> { where("stars <= 3") }

  def replied? = replied_at.present?
  def low?     = stars <= 3

  # Newest attachment order, capped — a caller that somehow got past the
  # validation still cannot flood the shop page.
  def photo_list = photos.attachments.first(MAX_PHOTOS)

  private

  def photos_are_reasonable
    return unless photos.attached?
    errors.add(:photos, :too_many, count: MAX_PHOTOS) if photos.attachments.size > MAX_PHOTOS
    photos.each do |att|
      blob = att.blob
      next if blob.nil?
      errors.add(:photos, :invalid) unless PHOTO_TYPES.include?(blob.content_type)
      errors.add(:photos, :too_large, count: PHOTO_MAX_BYTES / 1.megabyte) if blob.byte_size.to_i > PHOTO_MAX_BYTES
    end
  end
end
