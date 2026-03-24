class OpenskyService
  extend HttpClient
  extend SnapshotRecorder

  # Use Cloudflare Worker proxy when OPENSKY_PROXY_URL is set (bypasses cloud IP blocking)
  PROXY_URL = ENV["OPENSKY_PROXY_URL"]&.chomp("/")
  BASE_URL = PROXY_URL ? "#{PROXY_URL}/api" : "https://opensky-network.org/api"
  TOKEN_URL = PROXY_URL ? "#{PROXY_URL}/auth/token" : "https://auth.opensky-network.org/auth/realms/opensky-network/protocol/openid-connect/token"
  CACHE_TTL = 15

  ROUTE_CACHE_MAX = 500

  @last_fetch_at = nil
  @route_cache = {}
  @access_token = nil
  @token_expires_at = 0

  def self.fetch_flights(bounds: {})
    # OpenSky blocks cloud provider IPs (Heroku/AWS) — skip when disabled
    return [] if ENV["OPENSKY_DISABLED"].present?

    if @last_fetch_at.nil? || (Time.now.to_f - @last_fetch_at) > CACHE_TTL
      response = fetch_from_api(bounds)
      if response
        upsert_flights(response)
        @last_fetch_at = Time.now.to_f
      end
    end

    Flight.where("updated_at > ?", 2.minutes.ago).within_bounds(bounds)
  end

  def self.fetch_route(callsign)
    return { error: "No callsign" } if callsign.blank?
    return { error: "OpenSky disabled" } if ENV["OPENSKY_DISABLED"].present?

    cached = @route_cache[callsign]
    return cached if cached

    uri = URI("#{BASE_URL}/routes?callsign=#{CGI.escape(callsign)}")
    token = obtain_token
    headers = self.proxy_headers
    headers["Authorization"] = "Bearer #{token}" if token

    data = http_get(uri, headers: headers, open_timeout: 5, read_timeout: 10)
    return { error: "Route not found" } unless data

    result = {
      callsign: data["callsign"],
      route: data["route"],
      operator_iata: data["operatorIata"],
      flight_number: data["flightNumber"],
      raw_payload: data,
    }
    # LRU eviction: drop oldest entries when cache exceeds limit
    @route_cache.shift while @route_cache.size >= ROUTE_CACHE_MAX
    @route_cache[callsign] = result
    result
  end

  private

  def self.obtain_token
    return nil unless ENV["OPENSKY_ID"].present? && ENV["OPENSKY_SECRET"].present?
    return @access_token if @access_token && Time.now.to_f < @token_expires_at

    uri = URI(TOKEN_URL)
    data = http_post(uri, form_data: {
      "grant_type" => "client_credentials",
      "client_id" => ENV["OPENSKY_ID"],
      "client_secret" => ENV["OPENSKY_SECRET"]
    })

    if data
      @access_token = data["access_token"]
      @token_expires_at = Time.now.to_f + (data["expires_in"] || 1800) - 60
      Rails.logger.info("OpenSky: obtained OAuth token (expires in #{data["expires_in"]}s)")
      @access_token
    end
  end

  def self.fetch_from_api(bounds = {})
    uri = URI("#{BASE_URL}/states/all")
    uri.query = URI.encode_www_form(bounds) if bounds.size == 4

    token = obtain_token
    headers = proxy_headers
    headers["Authorization"] = "Bearer #{token}" if token

    http_get(uri, headers: headers)
  end

  def self.proxy_headers
    h = {}
    h["X-Proxy-Key"] = ENV["OPENSKY_PROXY_KEY"] if ENV["OPENSKY_PROXY_KEY"].present?
    h
  end

  def self.upsert_flights(data)
    states = data["states"]
    return if states.blank?

    now = Time.current
    records = states.filter_map do |s|
      next if s[5].nil? || s[6].nil?

      icao = s[0]
      cs = s[1]&.strip

      {
        icao24: icao,
        callsign: cs,
        origin_country: s[2],
        longitude: s[5],
        latitude: s[6],
        altitude: s[7] || s[13],
        speed: s[9],
        heading: s[10],
        vertical_rate: s[11],
        on_ground: s[8],
        time_position: s[3],
        source: "opensky",
        military: MilitaryClassifier.military?(icao24: icao, callsign: cs),
        updated_at: now,
        created_at: now
      }
    end

    if records.any?
      Flight.upsert_all(records, unique_by: :icao24)
      record_flight_snapshots(records)
    end

    # Purge stale flights not updated in the last 5 minutes
    Flight.where(source: [nil, "opensky"]).where("updated_at < ?", 5.minutes.ago).delete_all
  end
end
