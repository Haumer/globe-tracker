class WeatherAlertRefreshService
  extend HttpClient
  extend Refreshable
  include TimelineRecorder
  include RefreshableDataService

  FEED_URL = "https://api.weather.gov/alerts/active?status=actual&severity=Extreme,Severe,Moderate".freeze

  refreshes model: WeatherAlert, interval: 10.minutes

  private

  def fetch_data
    self.class.http_get(
      URI(FEED_URL),
      headers: { "User-Agent" => "GlobeTracker/1.0 (weather-alerts)", "Accept" => "application/geo+json" },
      open_timeout: 10, read_timeout: 30,
      cache_key: "http:weather_alerts", cache_ttl: 15.minutes
    )
  end

  def parse_records(data)
    features = data["features"] || []
    now = Time.current

    features.filter_map do |f|
      props = f["properties"] || {}
      geo = f["geometry"]

      lat, lng = extract_centroid(geo)
      lat, lng = approximate_from_area(props["areaDesc"]) if lat.nil? && props["areaDesc"].present?
      next unless lat && lng

      {
        external_id: props["id"] || SecureRandom.hex(8),
        event: props["event"],
        severity: props["severity"],
        urgency: props["urgency"],
        certainty: props["certainty"],
        headline: props["headline"],
        description: props["description"]&.slice(0, 500),
        areas: props["areaDesc"]&.slice(0, 200),
        sender: props["senderName"],
        onset: props["onset"],
        expires: props["expires"],
        latitude: lat.round(4),
        longitude: lng.round(4),
        fetched_at: now,
        created_at: now,
        updated_at: now,
      }
    end
  end

  def upsert_records(records)
    WeatherAlert.upsert_all(records, unique_by: :external_id)
  end

  def after_upsert(_records)
    WeatherAlert.where("expires < ?", 72.hours.ago).delete_all
  end

  def timeline_config
    { event_type: "weather_alert", model_class: WeatherAlert, time_column: :onset }
  end

  # ── Geometry helpers ──

  def extract_centroid(geo)
    return [nil, nil] unless geo

    case geo["type"]
    when "Point"
      coords = geo["coordinates"]
      [coords[1], coords[0]] if coords&.size == 2
    when "Polygon"
      ring = geo["coordinates"]&.first
      return [nil, nil] unless ring&.any?
      [ring.sum { |c| c[1] } / ring.size.to_f, ring.sum { |c| c[0] } / ring.size.to_f]
    when "MultiPolygon"
      all_coords = geo["coordinates"]&.flatten(2) || []
      return [nil, nil] if all_coords.empty?
      [all_coords.sum { |c| c[1] } / all_coords.size.to_f, all_coords.sum { |c| c[0] } / all_coords.size.to_f]
    else
      [nil, nil]
    end
  end

  STATE_CENTROIDS = {
    "AL" => [32.8, -86.8], "AK" => [64.2, -152.5], "AZ" => [34.0, -111.1],
    "AR" => [35.2, -91.8], "CA" => [36.8, -119.4], "CO" => [39.1, -105.4],
    "CT" => [41.6, -72.7], "DE" => [38.9, -75.5], "FL" => [27.7, -81.5],
    "GA" => [32.2, -83.6], "HI" => [19.9, -155.6], "ID" => [44.1, -114.7],
    "IL" => [40.6, -89.4], "IN" => [40.3, -86.1], "IA" => [41.9, -93.1],
    "KS" => [38.5, -98.8], "KY" => [37.8, -84.3], "LA" => [31.2, -92.3],
    "ME" => [45.3, -69.4], "MD" => [39.0, -76.6], "MA" => [42.4, -71.4],
    "MI" => [44.3, -85.6], "MN" => [46.7, -94.7], "MS" => [32.3, -89.4],
    "MO" => [38.6, -92.2], "MT" => [46.8, -110.4], "NE" => [41.1, -99.8],
    "NV" => [38.8, -116.4], "NH" => [43.5, -71.6], "NJ" => [40.1, -74.4],
    "NM" => [34.8, -106.2], "NY" => [43.0, -75.0], "NC" => [35.6, -79.0],
    "ND" => [47.5, -100.5], "OH" => [40.4, -82.9], "OK" => [35.0, -97.1],
    "OR" => [43.8, -120.6], "PA" => [41.2, -77.2], "RI" => [41.6, -71.5],
    "SC" => [33.8, -81.2], "SD" => [43.9, -99.4], "TN" => [35.5, -86.6],
    "TX" => [31.1, -97.6], "UT" => [39.3, -111.1], "VT" => [44.0, -72.7],
    "VA" => [37.8, -78.2], "WA" => [47.4, -120.7], "WV" => [38.6, -80.5],
    "WI" => [43.8, -88.8], "WY" => [43.1, -107.6],
  }.freeze

  def approximate_from_area(area_desc)
    STATE_CENTROIDS.each do |code, coords|
      return coords if area_desc.include?(code)
    end
    [nil, nil]
  end
end
