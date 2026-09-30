# Fills in coordinates for branches that have an address but no pin yet.
#
#   bin/rails loyalty:geocode            # only the ones still missing
#   bin/rails loyalty:geocode FORCE=1    # re-look-up everything the merchant
#                                        # has not set by hand
#
# Runs inline rather than through Sidekiq so the output says what happened, and
# GeocoderService's own throttle keeps it inside Nominatim's usage policy.
namespace :loyalty do
  desc "Geocode outlet addresses (ENV: FORCE=1)"
  task geocode: :environment do
    ActsAsTenant.without_tenant do
      scope = Outlet.where.not(address: [nil, ""]).where(geocode_manual: false)
      scope = scope.where(latitude: nil) unless ENV["FORCE"] == "1"
      total = scope.count
      puts "#{total} chi nhánh cần tra toạ độ."
      done = 0
      scope.find_each do |outlet|
        hit = GeocoderService.lookup_line(outlet.address)
        if hit
          outlet.update_columns(latitude: hit.lat, longitude: hit.lon, geocoded_at: Time.current)
          done += 1
          puts "   ✓ #{outlet.name} → #{hit.lat.round(5)}, #{hit.lon.round(5)} (#{hit.precision}#{' · tương đối' if hit.approximate?})"
        else
          outlet.update_columns(geocoded_at: Time.current)
          puts "   · #{outlet.name} → không tìm thấy (#{outlet.address})"
        end
      end
      puts "\n✅ #{done}/#{total} chi nhánh có toạ độ."
    end
  end
end
