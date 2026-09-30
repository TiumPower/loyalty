class Outlet < ApplicationRecord
  acts_as_tenant(:workspace)

  belongs_to :workspace
  has_many :memberships, dependent: :nullify

  # Purchases, point transactions, ratings and vouchers all reference an outlet
  # with a foreign key, so deleting a branch that has traded raises
  # InvalidForeignKey — the database protects the history, but the app used to
  # turn that into a 500. A branch that has history is deactivated, not deleted.
  def history_count
    @history_count ||= Purchase.unscoped.where(outlet_id: id).count +
                       PointTransaction.unscoped.where(outlet_id: id).count +
                       Rating.unscoped.where(outlet_id: id).count +
                       Voucher.unscoped.where(used_outlet_id: id).count
  end

  def destroyable? = history_count.zero?

  validates :name, presence: true
  validate  :open_hours_look_like_times
  validates :latitude,  numericality: { greater_than_or_equal_to: -90,  less_than_or_equal_to: 90 },  allow_nil: true
  validates :longitude, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }, allow_nil: true

  # Look the address up whenever it changes — and on the first save, so a branch
  # added today has coordinates without anyone thinking about it.
  after_commit :geocode_later, on: [:create, :update], if: :should_geocode?

  scope :active, -> { where(active: true) }

  # ---- Opening hours -----------------------------------------------------
  #
  # One window a day, as "07:00"/"22:00" in settings["open_hours"]. A branch
  # that has not said gets no "open now" badge in the customer app rather than
  # a cheerful guess — the badge used to be a constant and told customers the
  # shop was open at three in the morning.
  HHMM = /\A([01]\d|2[0-3]):[0-5]\d\z/

  def opens_at  = settings.dig("open_hours", "open").presence
  def closes_at = settings.dig("open_hours", "close").presence
  def hours?    = opens_at.present? && closes_at.present?

  def open_hours=(pair)
    # The form sends ActionController::Parameters; a console or a test sends a Hash.
    pair = pair.respond_to?(:to_unsafe_h) ? pair.to_unsafe_h : pair.to_h
    from, to = pair.values_at("open", "close").map { |v| v.to_s.strip }
    self.settings = settings.merge(
      "open_hours" => (from.blank? && to.blank? ? nil : { "open" => from, "close" => to })
    ).compact
  end

  # Whether the branch is open at `at`. A window that wraps past midnight
  # (22:00–02:00) is open on either side of it.
  def open_at?(at = Time.zone.now)
    return nil unless hours?
    now = at.strftime("%H:%M")
    closes_at > opens_at ? (now >= opens_at && now < closes_at) : (now >= opens_at || now < closes_at)
  end

  def located? = latitude.present? && longitude.present?

  # Coordinates for the customer app to measure against, as plain floats.
  def coords = located? ? [latitude.to_f, longitude.to_f] : nil

  private

  def should_geocode?
    return false if geocode_manual?
    return false if address.blank?
    # The "tự lấy toạ độ" button already did this lookup, for this address, a
    # second ago — the controller stamps geocoded_at to say so. Queuing the job
    # anyway would spend a Nominatim request to arrive at the same answer.
    return false if saved_change_to_geocoded_at? && located?
    # Re-run when the address moved, or when we have never looked.
    saved_change_to_address? || latitude.blank?
  end

  def geocode_later = GeocodeOutletJob.perform_later(id)

  def open_hours_look_like_times
    return unless settings.is_a?(Hash) && settings["open_hours"].present?
    [opens_at, closes_at].each do |v|
      errors.add(:base, :invalid_hours) unless v.to_s.match?(HHMM)
    end
  end
end
