class EarthquakeRefreshService
  extend HttpClient
  extend Refreshable
  include TimelineRecorder
  include RefreshableDataService

  FEED_URL = "https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/2.5_day.geojson".freeze

  refreshes model: Earthquake, interval: 5.minutes

  private

  def fetch_data
    self.class.http_get(URI(FEED_URL), open_timeout: 10, read_timeout: 30,
                        cache_key: "http:earthquake_feed", cache_ttl: 15.minutes)
  end

  def parse_records(data)
    features = data["features"] || []
    now = Time.current

    features.filter_map do |feature|
      props = feature["properties"] || {}
      coords = feature.dig("geometry", "coordinates")
      next if coords.nil? || coords.length < 3

      {
        external_id: feature["id"],
        title: props["place"] || "Unknown",
        magnitude: props["mag"],
        magnitude_type: props["magType"] || "",
        latitude: coords[1].to_f,
        longitude: coords[0].to_f,
        depth: coords[2].to_f,
        event_time: props["time"] ? Time.at(props["time"] / 1000.0) : nil,
        url: props["url"],
        tsunami: props["tsunami"] == 1,
        alert: props["alert"],
        fetched_at: now,
        created_at: now,
        updated_at: now,
      }
    end
  end

  def upsert_records(records)
    Earthquake.upsert_all(records, unique_by: :external_id)
  end

  def timeline_config
    { event_type: "earthquake", model_class: Earthquake, time_column: :event_time }
  end
end
