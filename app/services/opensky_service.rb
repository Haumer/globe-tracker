class OpenskyService
  BASE_URL = "https://opensky-network.org/api"
  TOKEN_URL = "https://auth.opensky-network.org/auth/realms/opensky-network/protocol/openid-connect/token"
  CACHE_TTL = 15

  @last_fetch_at = nil
  @route_cache = {}
  @access_token = nil
  @token_expires_at = 0

  def self.fetch_flights(bounds: {})
    if @last_fetch_at.nil? || (Time.now.to_f - @last_fetch_at) > CACHE_TTL
      response = fetch_from_api(bounds)
      if response
        upsert_flights(response)
        @last_fetch_at = Time.now.to_f
      end
    end

    # Only return flights updated in the last 2 minutes (discard stale data)
    filter_by_bounds(Flight.where("updated_at > ?", 2.minutes.ago), bounds)
  end

  def self.fetch_route(callsign)
    return { error: "No callsign" } if callsign.blank?

    cached = @route_cache[callsign]
    return cached if cached

    uri = URI("#{BASE_URL}/routes?callsign=#{CGI.escape(callsign)}")

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 5
    http.read_timeout = 10

    request = Net::HTTP::Get.new(uri)
    token = obtain_token
    request["Authorization"] = "Bearer #{token}" if token

    response = http.request(request)

    if response.is_a?(Net::HTTPSuccess)
      data = JSON.parse(response.body)
      result = {
        callsign: data["callsign"],
        route: data["route"],
        operator_iata: data["operatorIata"],
        flight_number: data["flightNumber"]
      }
      @route_cache[callsign] = result
      result
    else
      { error: "Route not found" }
    end
  rescue StandardError => e
    Rails.logger.error("OpenSky route lookup error: #{e.message}")
    { error: e.message }
  end

  private

  def self.obtain_token
    return nil unless ENV["OPENSKY_ID"].present? && ENV["OPENSKY_SECRET"].present?
    return @access_token if @access_token && Time.now.to_f < @token_expires_at

    uri = URI(TOKEN_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 5
    http.read_timeout = 10

    request = Net::HTTP::Post.new(uri)
    request.set_form_data(
      "grant_type" => "client_credentials",
      "client_id" => ENV["OPENSKY_ID"],
      "client_secret" => ENV["OPENSKY_SECRET"]
    )

    response = http.request(request)

    if response.is_a?(Net::HTTPSuccess)
      data = JSON.parse(response.body)
      @access_token = data["access_token"]
      @token_expires_at = Time.now.to_f + (data["expires_in"] || 1800) - 60  # refresh 60s early
      Rails.logger.info("OpenSky: obtained OAuth token (expires in #{data["expires_in"]}s)")
      @access_token
    else
      Rails.logger.error("OpenSky token error: #{response.code} #{response.body[0..200]}")
      nil
    end
  rescue StandardError => e
    Rails.logger.error("OpenSky token error: #{e.message}")
    nil
  end

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

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 30

    request = Net::HTTP::Get.new(uri)
    token = obtain_token
    request["Authorization"] = "Bearer #{token}" if token

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.warn("OpenSky API: #{response.code} #{response.body[0..100]}")
      return nil
    end

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

    # Purge flights not seen in the last 5 minutes
    Flight.where("updated_at < ?", 5.minutes.ago).delete_all
  end
end
