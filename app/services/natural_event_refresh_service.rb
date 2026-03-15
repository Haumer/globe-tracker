class NaturalEventRefreshService
  extend HttpClient
  extend Refreshable
  include TimelineRecorder
  include RefreshableDataService

  FEED_URL = "https://eonet.gsfc.nasa.gov/api/v3/events?status=open&limit=100".freeze

  refreshes model: NaturalEvent, interval: 5.minutes

  private

  def fetch_data
    self.class.http_get(URI(FEED_URL), open_timeout: 10, read_timeout: 30,
                        cache_key: "http:natural_events_feed", cache_ttl: 15.minutes)
  end

  def parse_records(data)
    events = data["events"] || []
    now = Time.current

    events.filter_map do |event|
      geo = event["geometry"]&.first
      category = event["categories"]&.first || {}
      next if geo.nil? || geo["coordinates"].nil?

      lat = geo["coordinates"][1]&.to_f
      lng = geo["coordinates"][0]&.to_f
      next if lat.nil? || lng.nil?

      {
        external_id: event["id"],
        title: event["title"],
        category_id: category["id"] || "unknown",
        category_title: category["title"] || "Unknown",
        latitude: lat,
        longitude: lng,
        event_date: geo["date"] ? Time.parse(geo["date"]) : nil,
        magnitude_value: geo["magnitudeValue"]&.to_f,
        magnitude_unit: geo["magnitudeUnit"],
        link: event["link"].is_a?(String) ? event["link"] : nil,
        sources: event["sources"] || [],
        geometry_points: event["geometry"] || [],
        fetched_at: now,
        created_at: now,
        updated_at: now,
      }
    end
  end

  def upsert_records(records)
    NaturalEvent.upsert_all(records, unique_by: :external_id)
  end

  def timeline_config
    { event_type: "natural_event", model_class: NaturalEvent, time_column: :event_date }
  end
end
