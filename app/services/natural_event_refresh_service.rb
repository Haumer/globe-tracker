class NaturalEventRefreshService
  extend HttpClient
  extend Refreshable
  include TimelineRecorder

  FEED_URL = "https://eonet.gsfc.nasa.gov/api/v3/events?status=open&limit=100".freeze

  refreshes model: NaturalEvent, interval: 5.minutes

  def refresh
    data = self.class.http_get(URI(FEED_URL), open_timeout: 10, read_timeout: 30)
    return 0 unless data

    events = data["events"] || []
    now = Time.current

    records = events.filter_map do |event|
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

    return 0 if records.empty?

    NaturalEvent.upsert_all(records, unique_by: :external_id)
    record_timeline_events(
      event_type: "natural_event",
      model_class: NaturalEvent,
      unique_key: :external_id,
      unique_values: records.map { |record| record[:external_id] },
      time_column: :event_date
    )

    records.size
  rescue StandardError => e
    Rails.logger.error("NaturalEventRefreshService: #{e.message}")
    0
  end
end
