class InternetOutageRefreshService
  extend HttpClient
  extend Refreshable

  IODA_BASE = "https://api.ioda.inetintel.cc.gatech.edu/v2".freeze

  refreshes model: InternetOutage, interval: 5.minutes

  class << self
    def cached_summary
      return [] unless File.exist?(summary_cache_path)
      JSON.parse(File.read(summary_cache_path), symbolize_names: true)
    rescue StandardError
      []
    end

    def summary_cache_path
      Rails.root.join("tmp", "internet_outage_summary.json")
    end
  end

  def refresh
    now = Time.current
    from_ts = 24.hours.ago.to_i
    until_ts = now.to_i

    events_data = fetch_ioda("#{IODA_BASE}/outages/events?entityType=country&from=#{from_ts}&until=#{until_ts}&limit=200&format=ioda")
    summary_data = fetch_ioda("#{IODA_BASE}/outages/summary?entityType=country&from=#{from_ts}&until=#{until_ts}")

    imported = upsert_events(events_data, now)
    write_summary(summary_data)
    imported
  rescue StandardError => e
    Rails.logger.error("InternetOutageRefreshService: #{e.message}")
    0
  end

  private

  def fetch_ioda(url)
    data = self.class.http_get(URI(url), open_timeout: 10, read_timeout: 30)
    data&.dig("data")
  end

  def upsert_events(events_data, now)
    return 0 unless events_data.is_a?(Array)

    records = events_data.filter_map do |event|
      entity = event["entity"] || {}
      next if entity["code"].blank?

      {
        external_id: "#{entity['code']}-#{event['datasource']}-#{event['from']}",
        entity_type: entity["type"] || "country",
        entity_code: entity["code"],
        entity_name: entity["name"],
        datasource: event["datasource"],
        score: event["score"]&.to_f,
        level: outage_level(event["score"]&.to_f || 0),
        condition: event["method"],
        started_at: event["from"] ? Time.at(event["from"]) : nil,
        ended_at: event["until"] ? Time.at(event["until"]) : nil,
        fetched_at: now,
        created_at: now,
        updated_at: now,
      }
    end

    return 0 if records.empty?

    InternetOutage.upsert_all(records, unique_by: :external_id)

    inserted = InternetOutage.where(external_id: records.map { |record| record[:external_id] })
    timeline_rows = inserted.map do |outage|
      {
        event_type: "internet_outage",
        eventable_type: "InternetOutage",
        eventable_id: outage.id,
        latitude: nil,
        longitude: nil,
        recorded_at: outage.started_at || now,
        created_at: now,
        updated_at: now,
      }
    end
    TimelineEvent.upsert_all(timeline_rows, unique_by: %i[eventable_type eventable_id]) if timeline_rows.any?

    records.size
  end

  def write_summary(summary_data)
    summaries = if summary_data.is_a?(Array)
      summary_data.filter_map do |summary|
        entity = summary["entity"] || {}
        scores = summary["scores"] || {}
        overall = scores["overall"]&.to_f || 0
        event_count = summary["event_cnt"]&.to_i || 0
        next if event_count < 1

        {
          code: entity["code"],
          name: entity["name"],
          score: overall.round(1),
          eventCount: event_count,
          level: outage_level(overall),
        }
      end.sort_by { |entry| -entry[:score] }.first(50)
    else
      []
    end

    File.write(self.class.summary_cache_path, summaries.to_json)
  end

  def outage_level(score)
    if score >= 100_000 then "critical"
    elsif score >= 10_000 then "severe"
    elsif score >= 1_000 then "moderate"
    else "minor"
    end
  end
end
