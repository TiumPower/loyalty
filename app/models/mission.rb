class Mission < ApplicationRecord
  acts_as_tenant(:workspace)

  TYPES = %w[checkin spend visit refer review social_share].freeze
  # Mission types completed by submitting a photo for review (manual or AI).
  PHOTO_PROOF_TYPES = %w[review social_share].freeze
  PROOF_PLATFORMS = %w[facebook instagram tiktok zalo].freeze
  PLATFORM_LABELS = {
    "facebook" => "Facebook", "instagram" => "Instagram",
    "tiktok" => "TikTok", "zalo" => "Zalo"
  }.freeze
  PLATFORM_ICONS = {
    "facebook" => "📘", "instagram" => "📸", "tiktok" => "🎵", "zalo" => "💬"
  }.freeze
  # "once" = one-time (never resets); daily/weekly recur each period.
  PERIODS = %w[once daily weekly].freeze

  belongs_to :workspace
  has_many :mission_progresses, dependent: :destroy

  # Photo-proof missions (review / social share) are inherently one-time — you
  # can't "share to Facebook" again every day for points — so force them to once.
  before_validation { self.period = "once" if photo_proof? }

  validates :title, presence: true
  validates :mission_type, inclusion: { in: TYPES }
  validates :period, inclusion: { in: PERIODS }
  # Photo-proof missions are single-submission, not incremental counters.
  validates :goal, inclusion: { in: [ 1 ] }, if: :photo_proof?

  scope :active,  -> { where(active: true) }
  scope :ordered, -> { order(:position, :id) }

  def photo_proof? = mission_type.in?(PHOTO_PROOF_TYPES)

  # Points awarded for a completion. social_share can pay per-platform via
  # proof_config["platforms"][platform] (0 = use the flat rate); everything else
  # uses the flat rate.
  def points_for(platform = nil)
    per = platform && proof_config.dig("platforms", platform.to_s)
    per.to_i.positive? ? per.to_i : reward_points
  end

  # A social_share mission targets exactly ONE network (the merchant's multi-select
  # is expanded into one mission per network on create).
  def platform
    proof_config.is_a?(Hash) ? proof_config["platform"].presence : nil
  end

  # Which social networks the customer may use for this mission. A per-platform
  # mission returns just its own network; legacy multi-platform missions fall back
  # to their configured list (all supported when unrestricted).
  def allowed_platforms
    return [ platform ] if platform.present?
    configured = (proof_config.is_a?(Hash) ? proof_config["platforms"] : nil).to_h.keys
    (configured & PROOF_PLATFORMS).presence || PROOF_PLATFORMS
  end

  def display_icon
    icon.presence || {
      "checkin" => "📍", "spend" => "💳", "visit" => "🏪", "refer" => "🤝",
      "review" => "⭐", "social_share" => "📣"
    }[mission_type]
  end

  # Current period bucket key (auto-resets progress each day/week).
  def current_period_key(time = Time.current)
    case period
    when "weekly" then time.strftime("%G-W%V")
    when "daily"  then time.strftime("%Y-%m-%d")
    else "once" # one-time: a single permanent bucket, never resets
    end
  end

  def progress_for(member)
    mission_progresses.find_or_initialize_by(member: member, period_key: current_period_key) do |mp|
      mp.workspace = workspace
    end
  end
end
