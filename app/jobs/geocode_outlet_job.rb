# Looks up a branch's coordinates from the address the merchant typed.
#
# Runs in the background because Nominatim's usage policy allows about one
# request a second and a lookup makes several — a merchant saving a branch
# should not wait for it, and a failed lookup must not fail the save.
class GeocodeOutletJob < ApplicationJob
  queue_as :default

  def perform(outlet_id)
    ActsAsTenant.without_tenant do
      outlet = Outlet.find_by(id: outlet_id)
      return if outlet.nil? || outlet.address.blank?
      # A coordinate the merchant set by hand is theirs; never overwrite it.
      return if outlet.geocode_manual?

      hit = GeocoderService.lookup_line(outlet.address)
      return outlet.update_columns(geocoded_at: Time.current) if hit.nil?

      outlet.update_columns(latitude: hit.lat, longitude: hit.lon, geocoded_at: Time.current)
    end
  rescue => e
    Rails.logger.error("[GeocodeOutletJob] outlet=#{outlet_id} #{e.class}: #{e.message}")
  end
end
