require "net/http"
require "json"

class OpenskyService
  BASE_URL = "https://opensky-network.org/api"
  CACHE_TTL = 10.seconds

  def self.fetch_flights(bounds: {})
    # Return cached data if fresh enough
    latest = Flight.order(updated_at: :desc).first
    if latest && latest.updated_at > CACHE_TTL.ago
      return filter_by_bounds(Flight.all, bounds)
    end

    response = fetch_from_api(bounds)
    return filter_by_bounds(Flight.all, bounds) unless response

    upsert_flights(response)
    filter_by_bounds(Flight.all, bounds)
  end

  def self.fetch_route(callsign)
    return { error: "No callsign" } if callsign.blank?

    # Check Rails cache first
    cache_key = "opensky_route_#{callsign}"
    cached = Rails.cache.read(cache_key)
    return cached if cached

    uri = URI("#{BASE_URL}/routes?callsign=#{CGI.escape(callsign)}")

    if ENV["OPENSKY_USERNAME"].present? && ENV["OPENSKY_PASSWORD"].present?
      uri.user = ENV["OPENSKY_USERNAME"]
      uri.password = ENV["OPENSKY_PASSWORD"]
    end

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 5
    http.read_timeout = 10

    request = Net::HTTP::Get.new(uri)
    response = http.request(request)

    if response.is_a?(Net::HTTPSuccess)
      data = JSON.parse(response.body)
      result = {
        callsign: data["callsign"],
        route: data["route"],
        operator_iata: data["operatorIata"],
        flight_number: data["flightNumber"]
      }
      Rails.cache.write(cache_key, result, expires_in: 1.hour)
      result
    else
      { error: "Route not found" }
    end
  rescue StandardError => e
    Rails.logger.error("OpenSky route lookup error: #{e.message}")
    { error: e.message }
  end

  private

  def self.filter_by_bounds(scope, bounds)
    return scope if bounds.blank? || bounds.size < 4

    scope.where(latitude: bounds[:lamin]..bounds[:lamax],
                longitude: bounds[:lomin]..bounds[:lomax])
  end

  def self.fetch_from_api(bounds = {})
    uri = URI("#{BASE_URL}/states/all")

    # Pass bounding box to OpenSky to limit response size
    if bounds.size == 4
      uri.query = URI.encode_www_form(bounds)
    end

    if ENV["OPENSKY_USERNAME"].present? && ENV["OPENSKY_PASSWORD"].present?
      uri.user = ENV["OPENSKY_USERNAME"]
      uri.password = ENV["OPENSKY_PASSWORD"]
    end

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 30

    request = Net::HTTP::Get.new(uri)
    response = http.request(request)

    return nil unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue StandardError => e
    Rails.logger.error("OpenSky API error: #{e.message}")
    nil
  end

  def self.upsert_flights(data)
    states = data["states"]
    return if states.blank?

    now = Time.current
    records = states.filter_map do |s|
      next if s[5].nil? || s[6].nil?

      {
        icao24: s[0],
        callsign: s[1]&.strip,
        origin_country: s[2],
        longitude: s[5],
        latitude: s[6],
        altitude: s[7] || s[13],
        speed: s[9],
        heading: s[10],
        vertical_rate: s[11],
        on_ground: s[8],
        time_position: s[3],
        updated_at: now,
        created_at: now
      }
    end

    Flight.upsert_all(records, unique_by: :icao24) if records.any?
  end
end
