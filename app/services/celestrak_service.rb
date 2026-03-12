class CelestrakService
  BASE_URL = "https://celestrak.org/NORAD/elements/gp.php"
  CACHE_TTL = 6 * 3600 # 6 hours in seconds

  CATEGORY_GROUPS = {
    "stations" => "stations",
    "starlink" => "starlink",
    "gps-ops" => "gps-ops",
    "glonass" => "glo-ops",              # Russian GLONASS navigation
    "galileo" => "galileo",              # European Galileo navigation
    "weather" => "weather",
    "resource" => "resource",
    "science" => "science",
    "military" => "military",
    "geo" => "geo",
    "iridium" => "iridium",
    "oneweb" => "oneweb",
    "planet" => "planet",
    "spire" => "spire",
    "gnss" => "gnss",
    "tdrss" => "tdrss",
    "radar" => "radar",
    "sbas" => "sbas",
    "cubesat" => "cubesat",
    "amateur" => "amateur",
    "sarsat" => "sarsat",
    "last-30-days" => "last-30-days",    # Recently launched — often military or classified
    "analyst" => "analyst",              # Classified/unacknowledged (NRO, etc.)
    "geodetic" => "geodetic",
    "dmc" => "dmc",
    "argos" => "argos",
    "intelsat" => "intelsat",
    "ses" => "ses",
    "x-comm" => "x-comm",
    "molniya" => "molniya",
    "beidou" => "beidou",
    "globalstar" => "globalstar",
  }.freeze

  class << self
    def fetch_satellites(category: nil)
      scope = Satellite.all
      scope = scope.where(category: category) if category.present?
      scope
    end

    def refresh_if_stale(category: nil, force: false)
      return 0 if !force && !stale?(category: category)

      if category.present? && CATEGORY_GROUPS.key?(category)
        fetch_and_upsert(group: CATEGORY_GROUPS[category], category: category)
        1
      else
        # Fetch specific categories (not the massive "active" group)
        CATEGORY_GROUPS.each do |cat, group|
          fetch_and_upsert(group: group, category: cat)
        end
        CATEGORY_GROUPS.size
      end
    end

    def stale?(category: nil)
      latest_updated_at(category: category).blank? || latest_updated_at(category: category) < CACHE_TTL.seconds.ago
    end

    private

    def latest_updated_at(category:)
      scope = Satellite.all
      scope = scope.where(category: category) if category.present?
      scope.maximum(:updated_at)
    end

    def fetch_and_upsert(group:, category:)
      uri = URI("#{BASE_URL}?GROUP=#{group}&FORMAT=tle")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 15
      http.read_timeout = 30
      response = http.request(Net::HTTP::Get.new(uri))

      return unless response.is_a?(Net::HTTPSuccess)

      satellites = parse_tle(response.body, category)
      upsert_satellites(satellites)
    end

    def parse_tle(body, category)
      lines = body.strip.split("\n").map(&:strip)
      satellites = []

      i = 0
      while i + 2 < lines.length
        name = lines[i]
        line1 = lines[i + 1]
        line2 = lines[i + 2]

        # Validate TLE format: line1 starts with "1 ", line2 starts with "2 "
        if line1.start_with?("1 ") && line2.start_with?("2 ")
          norad_id = line1[2..6].strip.to_i

          display_name = name.strip
          # Classified satellites from analyst group are named "UNKNOWN" — use NORAD ID
          display_name = "CLASSIFIED #{norad_id}" if display_name == "UNKNOWN" && category == "analyst"

          satellites << {
            name: display_name,
            tle_line1: line1,
            tle_line2: line2,
            category: category,
            norad_id: norad_id
          }
          i += 3
        else
          # Skip malformed entries
          i += 1
        end
      end

      satellites
    end

    def upsert_satellites(satellites)
      return if satellites.empty?

      now = Time.current
      records = satellites.map do |sat|
        classification = SatelliteClassifier.classify(sat[:name])
        sat.merge(
          operator: classification[:operator],
          mission_type: classification[:mission_type],
          created_at: now,
          updated_at: now,
        )
      end

      Satellite.upsert_all(
        records,
        unique_by: :norad_id,
        update_only: %i[name tle_line1 tle_line2 category operator mission_type]
      )

      record_tle_snapshots(satellites, now)
    end

    def record_tle_snapshots(satellites, now)
      norad_ids = satellites.map { |s| s[:norad_id] }

      # Fetch the most recent TLE snapshot per satellite to dedup
      last_tles = SatelliteTleSnapshot
        .where(norad_id: norad_ids)
        .where("recorded_at > ?", 1.hour.ago)
        .select("DISTINCT ON (norad_id) norad_id, tle_line1, tle_line2")
        .order(:norad_id, recorded_at: :desc)
        .index_by(&:norad_id)

      snapshots = satellites.filter_map do |sat|
        last = last_tles[sat[:norad_id]]
        # Skip if TLE lines haven't changed since last snapshot
        next if last && last.tle_line1 == sat[:tle_line1] && last.tle_line2 == sat[:tle_line2]

        {
          norad_id: sat[:norad_id],
          name: sat[:name],
          tle_line1: sat[:tle_line1],
          tle_line2: sat[:tle_line2],
          category: sat[:category],
          recorded_at: now,
        }
      end

      SatelliteTleSnapshot.insert_all(snapshots) if snapshots.any?
    rescue => e
      Rails.logger.error("TLE snapshot recording error: #{e.message}")
    end
  end
end
