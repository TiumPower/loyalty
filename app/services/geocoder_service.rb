# Turns a Vietnamese street address into map coordinates using Nominatim
# (OpenStreetMap) — free and key-less, so a shop gets coordinates just by filling
# in the branch address it already types.
#
# Ported from Estate, where the Vietnamese-address handling below was worked out
# the hard way; the notes are kept because they are what stops a branch landing
# fifteen kilometres from the door.
#
# Vietnamese addresses need more than a single query:
#   * Street names repeat across the country (there is a "Nguyễn Hữu Cảnh" in
#     several places), so we first resolve the district/city into an anchor and
#     then search for the street **inside a box around it**, picking the nearest
#     candidate. Without that, a branch in Bình Thạnh lands 15 km up the highway.
#   * The 2025 ward merger renamed districts, so the old district name often no
#     longer matches OSM text. The box does the constraining instead of the text.
#   * OSM rarely knows house numbers, so a hit is reported with its precision and
#     the UI says "vị trí tương đối" when it is only district/city level.
#
# Never raises: a failed lookup returns nil and the caller simply shows no
# distance (or keeps the coordinates a merchant typed by hand). Nominatim's usage policy wants
# an identifying User-Agent and ≤ 1 request/second — hence the throttle + cache.
module GeocoderService
  module_function

  ENDPOINT  = "https://nominatim.openstreetmap.org/search"
  CACHE_TTL = 30.days
  THROTTLE  = 1.1 # seconds between calls, per Nominatim's usage policy

  # Half-width of the search box around the anchor, in degrees (~110 km each).
  # A district is small; a whole province needs room.
  PAD = { "district" => 0.08, "city" => 0.30 }.freeze

  # Vietnam's bounding box — a match outside it is a bad match.
  VN_BOUNDS = { min_lat: 8.1, max_lat: 23.5, min_lon: 102.1, max_lon: 109.6 }.freeze

  Result = Struct.new(:lat, :lon, :display_name, :precision, keyword_init: true) do
    # district/city precision = a neighbourhood centre, not the actual door.
    def approximate? = %w[district city].include?(precision)
  end

  # Landlords write addresses the Vietnamese way; OSM indexes the spelled-out
  # forms. Expanding the common abbreviations turns a miss into a hit.
  ABBREVIATIONS = [
    [/\bTP\.?\s*HCM\b/i,         "Thành phố Hồ Chí Minh"],
    [/\bTPHCM\b/i,               "Thành phố Hồ Chí Minh"],
    [/\bHCM\b/i,                 "Hồ Chí Minh"],
    [/\bSài\s*Gòn\b/i,           "Hồ Chí Minh"],
    [/\bTP\.\s*/i,               "Thành phố "],
    [/\bQ\.?\s*(\d+)\b/i,        'Quận \1'],
    [/\bP\.?\s*(\d+)\b/i,        'Phường \1'],
    [/\bH\.\s*/i,                "Huyện "],
    [/\bX\.\s*/i,                "Xã "],
    [/\bTT\.\s*/i,               "Thị trấn "]
  ].freeze

  # Loyalty keeps one address string per branch ("12 Nguyễn Ư Dĩ, Thảo Điền,
  # TP. Thủ Đức"), so split it on commas into the parts `lookup` wants. The last
  # part is the city, the one before it the district, and whatever is left at
  # the front is the street.
  def lookup_line(address)
    parts = address.to_s.split(",").map { |p| p.strip.presence }.compact
    return nil if parts.empty?
    city     = parts.pop if parts.size > 1
    district = parts.pop if parts.size > 1
    ward     = parts.pop if parts.size > 1
    lookup(address_line: parts.join(", ").presence, ward: ward, district: district, city: city)
  end

  # → Result, or nil when nothing resolves.
  def lookup(address_line: nil, ward: nil, district: nil, city: nil)
    street, ward, district, city = [address_line, ward, district, city].map { |p| normalize(p) }

    anchor, anchor_precision = area_hit(district, city)
    box = anchor ? viewbox(anchor, PAD.fetch(anchor_precision, 0.3)) : nil

    if street.present?
      # With an anchor the box does the constraining, so the query stays short:
      # long queries full of renamed districts drag the match somewhere else.
      queries = anchor ? [[street, ward], [street]] : [[street, ward, district, city], [street, district, city]]
      queries.each do |parts|
        hit = search(query_for(parts), viewbox: box, near: anchor, expect: street_name(street))
        return result(hit, "street") if hit
      end
    end

    if ward.present?
      hit = search(query_for(anchor ? [ward] : [ward, district, city]), viewbox: box, near: anchor, expect: ward)
      return result(hit, "ward") if hit
    end

    anchor ? result(anchor, anchor_precision) : nil
  end

  # Coarse anchor: the district, else the city. → [hit, precision] or [nil, nil].
  def area_hit(district, city)
    if district.present?
      hit = search(query_for([district, city]))
      return [hit, "district"] if hit
    end
    if city.present?
      hit = search(query_for([city]))
      return [hit, "city"] if hit
    end
    [nil, nil]
  end

  # One cached Nominatim call. → { lat:, lon:, display_name: } or nil.
  # `near` picks the candidate closest to the anchor instead of OSM's own first.
  def search(query, viewbox: nil, near: nil, expect: nil)
    return nil if query.blank?
    key = Digest::MD5.hexdigest([query, viewbox].compact.join("|"))
    # Cache the miss too (as []) — a query OSM doesn't know won't start working
    # on the next page load, and every retry costs a throttled second.
    candidates = Rails.cache.fetch("geocode/v2/#{key}", expires_in: CACHE_TTL) { fetch(query, viewbox: viewbox) }
    pick(candidates, near: near, expect: expect)
  end

  def pick(candidates, near: nil, expect: nil)
    list = Array(candidates).select { |h| in_vietnam?(h[:lat], h[:lon]) }
    # Inside a box Nominatim will answer a street query with *some* nearby road
    # even when it doesn't know that street, so drop anything whose name doesn't
    # actually contain what we asked for — better to fall back to the district
    # centre than to put the room on the wrong street.
    if expect.present?
      needle = squash(expect)
      list = list.select { |h| squash(h[:display_name]).include?(needle) } if needle.present?
    end
    return nil if list.empty?
    return list.first unless near
    list.min_by { |h| (h[:lat] - near[:lat])**2 + (h[:lon] - near[:lon])**2 }
  end

  # "12 Nguyễn Văn Trỗi" → "Nguyễn Văn Trỗi": OSM indexes the street, not the
  # house number, so the number must not be part of the name check.
  def street_name(street)
    street.to_s.sub(/\A[\d\s\/\-.,]*(?:số\s+)?[\d\s\/\-.,]*/i, "")
          .sub(/\A(đường|phố|hẻm|ngõ)\s+/i, "").strip
  end

  # Accent- and case-insensitive form for comparing place names.
  def squash(text)
    I18n.transliterate(text.to_s.dup.force_encoding("UTF-8")).downcase.gsub(/[^a-z0-9]+/, " ").strip
  end

  # → array of candidate hashes (possibly empty).
  def fetch(query, viewbox: nil)
    throttle!
    params = { format: "jsonv2", q: query, limit: 5, countrycodes: "vn", "accept-language": "vi" }
    # bounded=1 makes the viewbox a hard filter, not just a ranking hint.
    params.merge!(viewbox: viewbox, bounded: 1) if viewbox
    resp = connection.get(ENDPOINT, params)
    return [] unless resp.success?
    Array(JSON.parse(resp.body)).map do |hit|
      { lat: hit["lat"].to_f, lon: hit["lon"].to_f, display_name: hit["display_name"].to_s }
    end
  rescue Faraday::Error, JSON::ParserError => e
    Rails.logger.warn("[GeocoderService] #{query.inspect} → #{e.class}: #{e.message}")
    []
  end

  def normalize(part)
    text = part.to_s.dup.force_encoding("UTF-8").strip
    return nil if text.blank?
    ABBREVIATIONS.each { |pattern, full| text = text.gsub(pattern, full) }
    text.squeeze(" ").strip.presence
  end

  def query_for(parts)
    (Array(parts).compact_blank + ["Việt Nam"]).join(", ")
  end

  def viewbox(hit, pad)
    [hit[:lon] - pad, hit[:lat] + pad, hit[:lon] + pad, hit[:lat] - pad].map { |n| n.round(4) }.join(",")
  end

  def result(hit, precision)
    Result.new(lat: hit[:lat], lon: hit[:lon], display_name: hit[:display_name], precision: precision)
  end

  def in_vietnam?(lat, lon)
    lat.to_f.between?(VN_BOUNDS[:min_lat], VN_BOUNDS[:max_lat]) &&
      lon.to_f.between?(VN_BOUNDS[:min_lon], VN_BOUNDS[:max_lon])
  end

  # Process-local spacing between requests. Good enough: geocoding runs in a
  # background job on a single Sidekiq process, plus the odd interactive click.
  def throttle!
    if @last_call_at && (wait = THROTTLE - (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @last_call_at)) > 0
      sleep(wait)
    end
    @last_call_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def connection
    @connection ||= Faraday.new do |f|
      f.request :retry, max: 1, interval: 1, retry_statuses: [429, 500, 502, 503]
      f.headers["User-Agent"] = "Quenly/1.0 (#{ENV.fetch('MAIL_FROM', 'no-reply@tiumpower.com')})"
      f.options.timeout = 15
      f.options.open_timeout = 5
    end
  end
end
