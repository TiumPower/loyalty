class Campaign < ApplicationRecord
  acts_as_tenant(:workspace)
  # Refuses a reward that is off / sold out / ended (see the concern).
  include AssignableReward

  TYPES = %w[promo_voucher double_points happy_hour event flash_mission].freeze
  STATUSES = %w[draft scheduled running paused ended].freeze
  AUDIENCES = %w[all vip new at_risk birthday].freeze

  belongs_to :workspace
  belongs_to :reward, optional: true
  has_many :promo_codes, dependent: :destroy
  has_many :broadcasts, dependent: :nullify
  # `banner` is the image the campaign shows right now; `banner_library` keeps
  # every banner it has ever had so a merchant can switch back to an earlier one
  # without uploading it again. Both point at the SAME blobs, so `banner` must
  # not purge on replacement — the library owns the files and purges them.
  has_one_attached :banner, dependent: false
  has_many_attached :banner_library

  BANNER_TYPES = %w[image/png image/jpeg image/webp image/gif].freeze
  BANNER_MAX_BYTES = 6.megabytes
  # A generated banner is ~1MB, so the archive is capped and the oldest entries
  # beyond it are dropped (never the one currently in use).
  BANNER_LIBRARY_LIMIT = 12

  validates :name, presence: true
  validates :campaign_type, inclusion: { in: TYPES }
  validates :status, inclusion: { in: STATUSES }

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

  # ---- Banner ------------------------------------------------------------

  # Why an upload cannot be used, as a symbol the caller translates; nil = fine.
  def self.banner_upload_problem(upload)
    return :missing unless upload.respond_to?(:content_type)
    return :type unless BANNER_TYPES.include?(upload.content_type)
    size = upload.respond_to?(:size) ? upload.size : upload.tempfile.size
    return :size if size.to_i > BANNER_MAX_BYTES
    nil
  end

  # Makes `blob` the campaign's banner and files it in the library.
  #
  # `has_qr` says whether a scannable QR is already composited into the image.
  # It is remembered ON THE BLOB as well as on the record, because re-selecting
  # a library banner months later has to restore the right answer: the public
  # share page only adds a standalone QR when the banner carries none.
  def set_banner!(blob, has_qr: nil)
    has_qr = banner_blob_has_qr?(blob) if has_qr.nil?
    blob.update!(metadata: blob.metadata.merge("campaign_banner_qr" => has_qr))
    banner_library.attach(blob) unless banner_library_attachments.exists?(blob_id: blob.id)
    banner.attach(blob) unless banner_attachment&.blob_id == blob.id
    update_columns(banner_status: "ready", banner_has_qr: has_qr, updated_at: Time.current)
    prune_banner_library!
    true
  end

  def banner_blob_has_qr?(blob) = blob.metadata["campaign_banner_qr"].present?

  def current_banner_blob_id = banner_attachment&.blob_id

  # Newest first, so the strip on the campaign page reads like a history.
  def banner_library_items
    banner_library_attachments.includes(:blob).order(created_at: :desc, id: :desc).to_a
  end

  private

  def prune_banner_library!
    current = current_banner_blob_id
    banner_library_attachments.reload
                              .order(created_at: :desc, id: :desc)
                              .offset(BANNER_LIBRARY_LIMIT)
                              .each { |att| att.purge_later unless att.blob_id == current }
  end
end
