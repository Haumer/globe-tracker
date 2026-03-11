class SubmarineCableRefreshService
  extend HttpClient

  CABLE_GEO_URL = "https://www.submarinecablemap.com/api/v3/cable/cable-geo.json".freeze
  LANDING_GEO_URL = "https://www.submarinecablemap.com/api/v3/landing-point/landing-point-geo.json".freeze
  REFRESH_INTERVAL = 7.days

  class << self
    def refresh_if_stale(force: false)
      return 0 if !force && !stale?

      new.refresh
    end

    def stale?
      latest_fetch_at.blank? || latest_fetch_at < REFRESH_INTERVAL.ago
    end

    def latest_fetch_at
      SubmarineCable.maximum(:fetched_at)
    end

    def cached_landing_points
      return [] unless File.exist?(landing_points_cache_path)

      JSON.parse(File.read(landing_points_cache_path))
    rescue StandardError
      []
    end

    def landing_points_cache_path
      Rails.root.join("tmp", "submarine_landing_points.json")
    end
  end

  def refresh
    now = Time.current
    refresh_cables(now)
    write_landing_points
  rescue StandardError => e
    Rails.logger.error("SubmarineCableRefreshService: #{e.message}")
    0
  end

  private

  def refresh_cables(now)
    data = self.class.http_get(URI(CABLE_GEO_URL), open_timeout: 15, read_timeout: 60)
    return 0 unless data

    features = data["features"] || []
    cables_by_id = {}

    features.each do |feature|
      props = feature["properties"] || {}
      cable_id = props["id"]
      next if cable_id.blank?

      cables_by_id[cable_id] ||= {
        cable_id: cable_id,
        name: props["name"],
        color: props["color"] || "#939597",
        coordinates: [],
        fetched_at: now,
        created_at: now,
        updated_at: now,
      }

      coords = feature.dig("geometry", "coordinates")
      cables_by_id[cable_id][:coordinates].concat(coords) if coords.is_a?(Array)
    end

    records = cables_by_id.values
    return 0 if records.empty?

    SubmarineCable.upsert_all(records, unique_by: :cable_id)
    records.size
  end

  def write_landing_points
    data = self.class.http_get(URI(LANDING_GEO_URL), open_timeout: 15, read_timeout: 60)
    landing_points = (data&.dig("features") || []).filter_map do |feature|
      coords = feature.dig("geometry", "coordinates")
      props = feature["properties"] || {}
      next if coords.nil? || coords.length < 2

      {
        id: props["id"],
        name: props["name"],
        lng: coords[0].to_f,
        lat: coords[1].to_f,
      }
    end

    File.write(self.class.landing_points_cache_path, landing_points.to_json)
  end
end
