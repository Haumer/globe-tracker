require "net/http"

class CelestrakService
  BASE_URL = "https://celestrak.org/NORAD/elements/gp.php"
  CACHE_TTL = 6.hours

  CATEGORY_GROUPS = {
    "stations" => "stations",
    "starlink" => "starlink",
    "gps-ops" => "gps-ops",
    "weather" => "weather"
  }.freeze

  class << self
    def fetch_satellites(category: nil)
      refresh_data_if_needed(category)

      scope = Satellite.all
      scope = scope.where(category: category) if category.present?
      scope
    end

    private

    def refresh_data_if_needed(category)
      cache_key = cache_key_for(category)
      return if Rails.cache.read(cache_key)

      if category.present? && CATEGORY_GROUPS.key?(category)
        fetch_and_upsert(group: CATEGORY_GROUPS[category], category: category)
      else
        # Fetch specific categories (not the massive "active" group)
        CATEGORY_GROUPS.each do |cat, group|
          fetch_and_upsert(group: group, category: cat)
        end
      end

      Rails.cache.write(cache_key, true, expires_in: CACHE_TTL)
    end

    def cache_key_for(category)
      "celestrak_fetched_#{category || 'all'}"
    end

    def fetch_and_upsert(group:, category:)
      uri = URI("#{BASE_URL}?GROUP=#{group}&FORMAT=tle")
      response = Net::HTTP.get_response(uri)

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

          satellites << {
            name: name.strip,
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
        sat.merge(created_at: now, updated_at: now)
      end

      Satellite.upsert_all(
        records,
        unique_by: :norad_id,
        update_only: %i[name tle_line1 tle_line2 category]
      )
    end
  end
end
