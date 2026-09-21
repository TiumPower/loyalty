class Campaign < ApplicationRecord
  acts_as_tenant(:workspace)

  TYPES = %w[promo_voucher double_points happy_hour event flash_mission].freeze
  STATUSES = %w[draft scheduled running paused ended].freeze
  AUDIENCES = %w[all vip new at_risk birthday].freeze

  belongs_to :workspace
  belongs_to :reward, optional: true
  has_many :promo_codes, dependent: :destroy
  has_many :broadcasts, dependent: :nullify
  has_one_attached :banner

  validates :name, presence: true
  validates :campaign_type, inclusion: { in: TYPES }
  validates :status, inclusion: { in: STATUSES }
  # A sold-out reward can't be handed out, so a campaign built on one would send
  # customers to a QR that always refuses. Only checked when the reward is being
  # attached or swapped — an existing campaign whose prize ran out stays saveable.
  validate :reward_has_stock_left, if: -> { reward_id_changed? && reward.present? }

  before_create :ensure_share_slug

  scope :recent, -> { order(created_at: :desc) }

  # Stable public token for the shareable link (/c/:share_slug). Backfilled
  # lazily for rows created before this column existed.
  def ensure_share_slug
    self.share_slug ||= SecureRandom.urlsafe_base64(9).tr("-_", "xy")
  end

  def share_token!
    ensure_share_slug
    save!(validate: false) if share_slug_changed?
    share_slug
  end

  TYPE_LABELS = {
    "promo_voucher" => "Phát voucher (QR)", "double_points" => "Nhân đôi điểm",
    "happy_hour" => "Giờ vàng", "event" => "Sự kiện", "flash_mission" => "Nhiệm vụ chớp nhoáng"
  }.freeze
  AUDIENCE_LABELS = {
    "all" => "Tất cả khách", "vip" => "Khách VIP", "new" => "Khách mới",
    "at_risk" => "Sắp rời bỏ", "birthday" => "Sinh nhật"
  }.freeze

  def type_label     = I18n.t("merchant.campaign_types.#{campaign_type}", default: TYPE_LABELS[campaign_type])
  def audience_label = I18n.t("merchant.campaign_audiences.#{audience}", default: AUDIENCE_LABELS[audience])
  def content_value(key) = content.presence&.dig(key.to_s)

  def live?
    status == "running" &&
      (starts_at.nil? || starts_at <= Time.current) &&
      (ends_at.nil? || ends_at >= Time.current)
  end

  def status_label = I18n.t("merchant.campaign_statuses.#{status}", default: status)

  private

  def reward_has_stock_left
    return if reward.in_stock?
    # :base — the form prints full_messages, and an attribute prefix here would
    # read as "Reward ..." in front of an already complete sentence.
    errors.add(:base, I18n.t("merchant.campaigns.reward_sold_out", title: reward.title))
  end
end
