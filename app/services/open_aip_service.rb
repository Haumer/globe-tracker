class OpenAipService
  BASE_URL = "https://api.core.openaip.net/api"
  CACHE_TTL = 1.hour

  # Restricted=1, Danger=2, Prohibited=3, ADIZ=12, MATZ=14, Warning=18
  RELEVANT_TYPES = "1,2,3,14,18".freeze

  TYPE_LABELS = {
    1 => "Restricted Area",
    2 => "Danger",
    3 => "Prohibited",
    14 => "Military",
    18 => "Warning",
  }.freeze

  class << self
    def fetch_airspaces(bounds:)
      api_key = ENV["OPENAIP_API_KEY"].presence
      return [] unless api_key

      cache_key = "openaip:airspaces:#{bounds.values.map { |v| v.round(1) }.join(',')}"
      cached = Rails.cache.read(cache_key)
      return cached if cached

      result = fetch_all_pages(api_key, bounds)
      Rails.cache.write(cache_key, result, expires_in: CACHE_TTL) rescue nil
      result
    rescue => e
      Rails.logger.error("OpenAipService: #{e.message}")
      []
    end

    private

    def fetch_all_pages(api_key, bounds, max_pages: 3)
      all_items = []
      page = 1

      loop do
        break if page > max_pages

        uri = URI("#{BASE_URL}/airspaces")
        uri.query = URI.encode_www_form(
          type: RELEVANT_TYPES,
          bbox: "#{bounds[:lomin]},#{bounds[:lamin]},#{bounds[:lomax]},#{bounds[:lamax]}",
          limit: 200,
          page: page,
        )

        req = Net::HTTP::Get.new(uri)
        req["x-openaip-api-key"] = api_key

        resp = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 20) do |http|
          http.request(req)
        end

        break unless resp.is_a?(Net::HTTPSuccess)

        data = JSON.parse(resp.body)
        items = data["items"] || []
        break if items.empty?

        items.each do |item|
          parsed = parse_airspace(item)
          all_items << parsed if parsed
        end

        total_pages = data["totalPages"] || 1
        break if page >= total_pages

        page += 1
      end

      all_items
    end

    def parse_airspace(item)
      geometry = item["geometry"]
      return nil unless geometry

      lat, lng = centroid(geometry)
      return nil unless lat && lng

      type_code = item["type"].to_i
      reason = TYPE_LABELS[type_code] || "Restricted Area"

      alt_low = convert_altitude(item["lowerLimit"])
      alt_high = convert_altitude(item["upperLimit"]) || 18_000

      radius_m = estimate_radius(geometry)

      {
        id: "oaip-#{item['_id']}",
        lat: lat.round(6),
        lng: lng.round(6),
        radius_nm: (radius_m / 1852.0).round(1),
        radius_m: radius_m.round,
        alt_low_ft: alt_low || 0,
        alt_high_ft: alt_high,
        reason: reason,
        text: item["name"] || "Restricted Airspace",
        country: item["country"],
        effective_start: nil,
        effective_end: nil,
      }
    end

    def centroid(geometry)
      coords = geometry["coordinates"]
      return nil unless coords

      points = case geometry["type"]
               when "Point"
                 [[coords[0], coords[1]]]
               when "Polygon"
                 coords[0] || []
               when "MultiPolygon"
                 coords.flat_map { |poly| poly[0] || [] }
               else
                 []
               end

      return nil if points.empty?

      avg_lng = points.sum { |p| p[0] } / points.size.to_f
      avg_lat = points.sum { |p| p[1] } / points.size.to_f
      [avg_lat, avg_lng]
    end

    def estimate_radius(geometry)
      coords = geometry["coordinates"]
      return 5556 unless coords # default ~3nm

      points = case geometry["type"]
               when "Polygon" then coords[0] || []
               when "MultiPolygon" then coords.flat_map { |p| p[0] || [] }
               else return 5556
               end

      return 5556 if points.size < 3

      avg_lat = points.sum { |p| p[1] } / points.size.to_f
      avg_lng = points.sum { |p| p[0] } / points.size.to_f

      max_dist = points.map do |p|
        dlat = (p[1] - avg_lat) * 111_320
        dlng = (p[0] - avg_lng) * 111_320 * Math.cos(avg_lat * Math::PI / 180)
        Math.sqrt(dlat**2 + dlng**2)
      end.max

      [max_dist || 5556, 1000].max # min 1km
    end

    def convert_altitude(limit)
      return nil unless limit

      value = limit["value"].to_f
      unit = limit["unit"].to_i

      case unit
      when 0 then (value * 3.28084).round # meters → feet
      when 1 then value.round             # already feet
      when 6 then (value * 100).round     # flight level → feet
      else value.round
      end
    end
  end
end
