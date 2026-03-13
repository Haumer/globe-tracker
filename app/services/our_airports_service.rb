require "net/http"
require "csv"

class OurAirportsService
  extend Refreshable

  CSV_URL = "https://davidmegginson.github.io/ourairports-data/airports.csv".freeze
  INCLUDED_TYPES = %w[large_airport medium_airport].freeze

  refreshes model: Airport, interval: 7.days

  class << self
    def refresh_if_stale(force: false)
      return 0 if !force && !stale?
      fetch_and_upsert
    end

    private

    def fetch_and_upsert
      uri = URI(CSV_URL)
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 60) do |http|
        http.request(Net::HTTP::Get.new(uri))
      end

      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.error("OurAirportsService: HTTP #{response.code}")
        return 0
      end

      now = Time.current
      records = []

      body = response.body.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
      CSV.parse(body, headers: true) do |row|
        airport_type = row["type"]
        next if airport_type.blank?
        next if airport_type == "closed"

        lat = row["latitude_deg"]&.to_f
        lng = row["longitude_deg"]&.to_f
        next if lat.nil? || lng.nil? || (lat == 0.0 && lng == 0.0)

        name = row["name"].to_s.strip
        icao_code = row["ident"].to_s.strip
        next if icao_code.blank?

        is_military = military_airport?(name, airport_type)

        # Include large, medium, and military-detected airports
        next unless INCLUDED_TYPES.include?(airport_type) || is_military

        # Normalize military type
        effective_type = is_military && !INCLUDED_TYPES.include?(airport_type) ? "military" : airport_type

        records << {
          icao_code: icao_code,
          iata_code: row["iata_code"].presence,
          name: name,
          airport_type: effective_type,
          latitude: lat,
          longitude: lng,
          elevation_ft: row["elevation_ft"]&.to_i,
          country_code: row["iso_country"].to_s.strip.presence,
          municipality: row["municipality"].to_s.strip.presence,
          is_military: is_military,
          fetched_at: now,
          created_at: now,
          updated_at: now,
        }
      end

      if records.any?
        # Batch upsert in chunks to avoid exceeding PG parameter limits
        records.each_slice(2000) do |batch|
          Airport.upsert_all(batch, unique_by: :icao_code)
        end
      end

      Rails.logger.info("OurAirportsService: imported #{records.size} airports")
      records.size
    rescue StandardError => e
      Rails.logger.error("OurAirportsService: #{e.message}")
      0
    end

    def military_airport?(name, type)
      return true if type == "military"

      Airport::MILITARY_KEYWORDS.any? { |kw| name.to_s.include?(kw) }
    end
  end
end
