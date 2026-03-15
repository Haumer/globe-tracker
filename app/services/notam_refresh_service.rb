class NotamRefreshService
  extend HttpClient
  extend Refreshable
  include TimelineRecorder
  include RefreshableDataService

  refreshes model: Notam, interval: 15.minutes

  # Regions to poll for NOTAMs (FAA covers ~500nm radius per query)
  POLL_REGIONS = [
    { lat: 39, lon: -98,  label: "CONUS" },
    { lat: 50, lon: 10,   label: "Europe" },
    { lat: 28, lon: 47,   label: "Middle East" },
    { lat: 35, lon: 135,  label: "East Asia" },
    { lat: 5,  lon: 105,  label: "SE Asia" },
  ].freeze

  private

  def fetch_data
    records = []
    records.concat(fetch_faa_notams)
    records.concat(fetch_openaip_airspaces)
    records.presence
  end

  def parse_records(data)
    # Data is already parsed in fetch_data
    data
  end

  def upsert_records(records)
    Notam.upsert_all(records, unique_by: :external_id)
  end

  def after_upsert(_records)
    Notam.where("effective_end < ?", 48.hours.ago).where.not(effective_end: nil).delete_all
  end

  def timeline_config
    { event_type: "notam", model_class: Notam, time_column: :effective_start }
  end

  # ── FAA NOTAMs ──

  def fetch_faa_notams
    token = ENV["FAA_NOTAM_API_KEY"].presence
    return [] unless token

    now = Time.current
    records = []

    POLL_REGIONS.each do |region|
      uri = URI("https://external-api.faa.gov/notamapi/v1/notams")
      uri.query = URI.encode_www_form(
        responseFormat: "geoJson",
        notamType: "NOTAM",
        classification: "FDC",
        locationLongitude: region[:lon],
        locationLatitude: region[:lat],
        locationRadius: 500,
        featureType: "TFR",
        effectiveStartDate: now.strftime("%Y-%m-%dT%H:%M:%SZ"),
        effectiveEndDate: (now + 24.hours).strftime("%Y-%m-%dT%H:%M:%SZ"),
      )

      data = self.class.http_get(
        uri,
        headers: { "client_id" => token },
        open_timeout: 10, read_timeout: 20, retries: 1,
        cache_key: "http:faa_notams:#{region[:label]}", cache_ttl: 20.minutes
      )
      next unless data

      items = data["items"] || data["notams"] || []
      items.each do |item|
        parsed = parse_faa_notam(item, now)
        records << parsed if parsed
      end
    end

    records
  end

  def parse_faa_notam(item, now)
    props = item["properties"] || item
    text = props["text"] || props["notamText"] || ""

    lat = props.dig("coordinates", "latitude") || props["lat"]
    lng = props.dig("coordinates", "longitude") || props["lng"]

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

    radius_nm = 3
    radius_nm = $1.to_f if text =~ /(\d+(?:\.\d+)?)\s*(?:NM|NAUTICAL MILE)\s*RADIUS/i

    alt_low = 0
    alt_high = 18_000
    if text =~ /SFC\s*(?:TO|UP TO)\s*(?:FL)?(\d+)/i
      alt_high = $1.to_i
      alt_high *= 100 if alt_high < 1000
    end
    if text =~ /(\d+)\s*FT\s*(?:TO|UP TO|THRU)\s*(?:FL)?(\d+)/i
      alt_low = $1.to_i
      alt_high = $2.to_i
      alt_high *= 100 if alt_high < 1000
    end

    reason = "TFR"
    reason = "VIP Movement" if text =~ /VIP|POTUS|PRESIDENT/i
    reason = "Wildfire" if text =~ /WILDFIRE|FIRE/i
    reason = "Space Operations" if text =~ /SPACE|LAUNCH|ROCKET/i
    reason = "Sporting Event" if text =~ /STADIUM|SPORTING|SUPER BOWL|NASCAR/i
    reason = "Security" if text =~ /SECURITY|NATIONAL DEFENSE/i
    reason = "Hazard" if text =~ /HAZARD|UAS|DRONE/i

    ext_id = props["id"] || props["notamNumber"]
    return nil unless ext_id

    {
      external_id: "faa-#{ext_id}",
      source: "faa",
      latitude: lat.to_f,
      longitude: lng.to_f,
      radius_nm: radius_nm,
      radius_m: (radius_nm * 1852).round,
      alt_low_ft: alt_low,
      alt_high_ft: alt_high,
      reason: reason,
      text: text.truncate(200),
      country: nil,
      effective_start: props["effectiveStart"] || props["startDate"],
      effective_end: props["effectiveEnd"] || props["endDate"],
      fetched_at: now,
      created_at: now,
      updated_at: now,
    }
  end

  # ── OpenAIP Airspaces ──

  def fetch_openaip_airspaces
    now = Time.current
    records = []

    POLL_REGIONS.each do |region|
      bounds = {
        lamin: region[:lat] - 15, lamax: region[:lat] + 15,
        lomin: region[:lon] - 20, lomax: region[:lon] + 20,
      }

      items = OpenAipService.fetch_airspaces(bounds: bounds)
      items.each do |item|
        records << {
          external_id: item[:id],
          source: "openaip",
          latitude: item[:lat],
          longitude: item[:lng],
          radius_nm: item[:radius_nm],
          radius_m: item[:radius_m],
          alt_low_ft: item[:alt_low_ft],
          alt_high_ft: item[:alt_high_ft],
          reason: item[:reason],
          text: item[:text]&.truncate(200),
          country: item[:country],
          effective_start: nil,
          effective_end: nil,
          fetched_at: now,
          created_at: now,
          updated_at: now,
        }
      end
    end

    records.uniq { |r| r[:external_id] }
  end
end
