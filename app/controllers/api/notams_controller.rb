module Api
  class NotamsController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      token = ENV["FAA_NOTAM_API_KEY"].presence
      unless token
        # Return hardcoded well-known TFRs as fallback (Washington DC SFRA, Camp David, etc.)
        render json: fallback_tfrs
        return
      end

      bounds = {
        lamin: params[:lamin]&.to_f || -90,
        lamax: params[:lamax]&.to_f || 90,
        lomin: params[:lomin]&.to_f || -180,
        lomax: params[:lomax]&.to_f || 180,
      }

      notams = fetch_notams(token, bounds)
      expires_in 15.minutes, public: true
      render json: notams
    end

    private

    def fetch_notams(token, bounds)
      cache_key = "notams:#{bounds.values.map { |v| v.round(1) }.join(',')}"

      cached = Rails.cache.read(cache_key)
      return cached if cached

      uri = URI("https://external-api.faa.gov/notamapi/v1/notams")
      uri.query = URI.encode_www_form(
        responseFormat: "geoJson",
        notamType: "NOTAM",
        classification: "FDC",
        locationLongitude: ((bounds[:lomin] + bounds[:lomax]) / 2).round(2),
        locationLatitude: ((bounds[:lamin] + bounds[:lamax]) / 2).round(2),
        locationRadius: [500, ((bounds[:lamax] - bounds[:lamin]) * 60).round].min,
        featureType: "TFR",
        effectiveStartDate: Time.current.strftime("%Y-%m-%dT%H:%M:%SZ"),
        effectiveEndDate: (Time.current + 24.hours).strftime("%Y-%m-%dT%H:%M:%SZ"),
      )

      req = Net::HTTP::Get.new(uri)
      req["client_id"] = token

      resp = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 20) do |http|
        http.request(req)
      end

      return fallback_tfrs unless resp.is_a?(Net::HTTPSuccess)

      data = JSON.parse(resp.body)
      items = data["items"] || data["notams"] || []

      result = items.filter_map do |item|
        parse_notam(item)
      end

      Rails.cache.write(cache_key, result, expires_in: 15.minutes) rescue nil
      result
    rescue => e
      Rails.logger.error("NotamsController: #{e.message}")
      fallback_tfrs
    end

    def parse_notam(item)
      props = item["properties"] || item
      text = props["text"] || props["notamText"] || ""

      lat = props.dig("coordinates", "latitude") || props["lat"]
      lng = props.dig("coordinates", "longitude") || props["lng"]

      # Try GeoJSON geometry
      if item["geometry"]
        coords = item.dig("geometry", "coordinates")
        if coords
          if item["geometry"]["type"] == "Point"
            lng, lat = coords
          elsif item["geometry"]["type"] == "Polygon" && coords[0]
            ring = coords[0]
            lat = ring.sum { |c| c[1] } / ring.size.to_f
            lng = ring.sum { |c| c[0] } / ring.size.to_f
          end
        end
      end

      return nil unless lat && lng

      # Extract radius from text (nautical miles)
      radius_nm = 3 # default
      if text =~ /(\d+(?:\.\d+)?)\s*(?:NM|NAUTICAL MILE)\s*RADIUS/i
        radius_nm = $1.to_f
      end

      # Extract altitude from text
      alt_low = 0
      alt_high = 18000 # default FL180
      if text =~ /SFC\s*(?:TO|UP TO)\s*(?:FL)?(\d+)/i
        alt_high = $1.to_i
        alt_high *= 100 if alt_high < 1000
      end
      if text =~ /(\d+)\s*FT\s*(?:TO|UP TO|THRU)\s*(?:FL)?(\d+)/i
        alt_low = $1.to_i
        alt_high = $2.to_i
        alt_high *= 100 if alt_high < 1000
      end

      # Determine reason/type
      reason = "TFR"
      reason = "VIP Movement" if text =~ /VIP|POTUS|PRESIDENT/i
      reason = "Wildfire" if text =~ /WILDFIRE|FIRE/i
      reason = "Space Operations" if text =~ /SPACE|LAUNCH|ROCKET/i
      reason = "Sporting Event" if text =~ /STADIUM|SPORTING|SUPER BOWL|NASCAR/i
      reason = "Security" if text =~ /SECURITY|NATIONAL DEFENSE/i
      reason = "Hazard" if text =~ /HAZARD|UAS|DRONE/i

      {
        id: props["id"] || props["notamNumber"] || SecureRandom.hex(4),
        lat: lat.to_f,
        lng: lng.to_f,
        radius_nm: radius_nm,
        radius_m: (radius_nm * 1852).round,
        alt_low_ft: alt_low,
        alt_high_ft: alt_high,
        reason: reason,
        text: text.truncate(200),
        effective_start: props["effectiveStart"] || props["startDate"],
        effective_end: props["effectiveEnd"] || props["endDate"],
      }
    end

    def fallback_tfrs
      [
        { id: "DC-SFRA", lat: 38.8977, lng: -77.0365, radius_nm: 30, radius_m: 55560, alt_low_ft: 0, alt_high_ft: 18000, reason: "Washington DC SFRA", text: "Washington DC Special Flight Rules Area", effective_start: nil, effective_end: nil },
        { id: "DC-FRZ", lat: 38.8977, lng: -77.0365, radius_nm: 15, radius_m: 27780, alt_low_ft: 0, alt_high_ft: 18000, reason: "Washington DC FRZ", text: "Washington DC Flight Restricted Zone", effective_start: nil, effective_end: nil },
        { id: "P-56A", lat: 38.8977, lng: -77.0365, radius_nm: 0.65, radius_m: 1204, alt_low_ft: 0, alt_high_ft: 18000, reason: "White House", text: "Prohibited Area P-56A (White House)", effective_start: nil, effective_end: nil },
        { id: "P-56B", lat: 38.8935, lng: -77.0147, radius_nm: 0.35, radius_m: 648, alt_low_ft: 0, alt_high_ft: 18000, reason: "US Capitol", text: "Prohibited Area P-56B (US Capitol)", effective_start: nil, effective_end: nil },
        { id: "CAMP-DAVID", lat: 39.6479, lng: -77.4650, radius_nm: 3, radius_m: 5556, alt_low_ft: 0, alt_high_ft: 5000, reason: "Camp David", text: "Camp David TFR", effective_start: nil, effective_end: nil },
        { id: "AREA-51", lat: 37.2350, lng: -115.8111, radius_nm: 25, radius_m: 46300, alt_low_ft: 0, alt_high_ft: 99999, reason: "Restricted Area", text: "Restricted Area R-4808N (Nevada Test Range)", effective_start: nil, effective_end: nil },
        { id: "KENNEDY", lat: 28.5728, lng: -80.6490, radius_nm: 30, radius_m: 55560, alt_low_ft: 0, alt_high_ft: 99999, reason: "Space Operations", text: "Kennedy Space Center / Cape Canaveral launch operations", effective_start: nil, effective_end: nil },
        { id: "DISNEY", lat: 28.3852, lng: -81.5639, radius_nm: 3, radius_m: 5556, alt_low_ft: 0, alt_high_ft: 3000, reason: "Security", text: "Walt Disney World TFR", effective_start: nil, effective_end: nil },
      ]
    end
  end
end
