require "csv"
require "net/http"

class PowerPlantImportService
  CSV_URL = "https://raw.githubusercontent.com/wri/global-power-plant-database/master/output_database/global_power_plant_database.csv".freeze

  def self.import!
    Rails.logger.info("PowerPlantImportService: downloading CSV...")
    uri = URI(CSV_URL)
    response = Net::HTTP.get_response(uri)

    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.error("PowerPlantImportService: HTTP #{response.code}")
      return 0
    end

    now = Time.current
    records = []

    CSV.parse(response.body, headers: true, liberal_parsing: true) do |row|
      lat = row["latitude"]&.to_f
      lng = row["longitude"]&.to_f
      next if lat.nil? || lng.nil? || lat == 0.0 && lng == 0.0

      records << {
        gppd_idnr: row["gppd_idnr"],
        name: row["name"] || "Unknown",
        country_code: row["country"],
        country_name: row["country_long"],
        latitude: lat,
        longitude: lng,
        capacity_mw: row["capacity_mw"]&.to_f,
        primary_fuel: row["primary_fuel"],
        other_fuel: [row["other_fuel1"], row["other_fuel2"], row["other_fuel3"]].compact.reject(&:blank?).join(", ").presence,
        owner: row["owner"],
        commissioning_year: row["commissioning_year"]&.to_i.presence,
        source: row["source"],
        url: row["url"],
        created_at: now,
        updated_at: now,
      }
    end

    # Batch upsert
    imported = 0
    records.each_slice(2000) do |batch|
      PowerPlant.upsert_all(batch, unique_by: :gppd_idnr)
      imported += batch.size
      Rails.logger.info("PowerPlantImportService: #{imported}/#{records.size}")
    end

    CuratedPowerPlantSyncService.sync!

    Rails.logger.info("PowerPlantImportService: done — #{imported} plants")
    imported
  end
end
