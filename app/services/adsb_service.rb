class AdsbService
  extend HttpClient
  extend SnapshotRecorder

  BASE_URL = "https://api.adsb.lol/v2"
  CACHE_TTL = 10

  @last_fetch_at = nil
  @last_mil_fetch_at = nil

  def self.fetch_military
    if @last_mil_fetch_at.nil? || (Time.now.to_f - @last_mil_fetch_at) > CACHE_TTL
      uri = URI("#{BASE_URL}/mil")
      response = http_get(uri, headers: { "Accept" => "application/json" })
      if response
        upsert_flights(response)
        @last_mil_fetch_at = Time.now.to_f
      end
    end

    Flight.where(source: "adsb").where("updated_at > ?", 2.minutes.ago)
  end

  def self.fetch_flights(bounds: {})
    if @last_fetch_at.nil? || (Time.now.to_f - @last_fetch_at) > CACHE_TTL
      response = fetch_from_api(bounds)
      if response
        upsert_flights(response)
        @last_fetch_at = Time.now.to_f
      end
    end

    Flight.where(source: "adsb").where("updated_at > ?", 2.minutes.ago).within_bounds(bounds)
  end

  private

  def self.fetch_from_api(bounds)
    if bounds.present? && bounds.size == 4
      lat = ((bounds[:lamin] + bounds[:lamax]) / 2.0).round(2)
      lon = ((bounds[:lomin] + bounds[:lomax]) / 2.0).round(2)
      dlat = (bounds[:lamax] - bounds[:lamin]) / 2.0
      dlon = (bounds[:lomax] - bounds[:lomin]) / 2.0
      dist = [([dlat, dlon].max * 60).ceil, 250].min
      uri = URI("#{BASE_URL}/lat/#{lat}/lon/#{lon}/dist/#{dist}")
    else
      uri = URI("#{BASE_URL}/lat/0/lon/0/dist/250")
    end

    http_get(uri, headers: { "Accept" => "application/json" })
  end

  def self.upsert_flights(data)
    aircraft = data["ac"]
    return if aircraft.blank?

    now = Time.current
    records = aircraft.filter_map do |ac|
      next if ac["lat"].nil? || ac["lon"].nil?
      next if ac["seen"].to_i > 60 # skip aircraft not seen in last 60s

      alt_baro = ac["alt_baro"].is_a?(Numeric) ? ac["alt_baro"] : nil
      alt_geom = ac["alt_geom"].is_a?(Numeric) ? ac["alt_geom"] : nil
      altitude_ft = alt_geom || alt_baro
      altitude_m = altitude_ft ? (altitude_ft * 0.3048).round(1) : nil

      speed_kt = ac["gs"]
      speed_ms = speed_kt ? (speed_kt * 0.514444).round(1) : nil

      vrate_fpm = ac["baro_rate"] || ac["geom_rate"]
      vrate_ms = vrate_fpm ? (vrate_fpm * 0.00508).round(2) : nil

      on_ground = ac["alt_baro"] == "ground" || altitude_m.nil? || altitude_m < 50

      icao = ac["hex"]&.downcase
      cs = ac["flight"]&.strip

      {
        icao24: icao,
        callsign: cs,
        origin_country: nil,
        longitude: ac["lon"],
        latitude: ac["lat"],
        altitude: altitude_m,
        speed: speed_ms,
        heading: ac["track"],
        vertical_rate: vrate_ms,
        on_ground: on_ground,
        time_position: ac["seen"] ? (Time.now.to_i - ac["seen"].to_i) : Time.now.to_i,
        source: "adsb",
        registration: ac["r"],
        aircraft_type: ac["t"],
        nac_p: ac["nac_p"],
        military: MilitaryClassifier.military?(icao24: icao, callsign: cs),
        updated_at: now,
        created_at: now,
      }
    end

    if records.any?
      Flight.upsert_all(records, unique_by: :icao24)
      record_flight_snapshots(records)
    end

    # Purge stale ADSB flights not updated in the last 5 minutes
    Flight.where(source: "adsb").where("updated_at < ?", 5.minutes.ago).delete_all
  end
end
