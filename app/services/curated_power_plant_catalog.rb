class CuratedPowerPlantCatalog
  DATA_FILE = Rails.root.join("db", "data", "power_plant_profiles.json").freeze

  class << self
    def all
      return [] unless File.exist?(DATA_FILE)

      JSON.parse(File.read(DATA_FILE))
    rescue JSON::ParserError => error
      Rails.logger.error("CuratedPowerPlantCatalog parse failed: #{error.message}")
      []
    end

    def filtered(country_codes: nil)
      records = all
      return records if country_codes.blank?

      codes = normalize_codes(country_codes)
      records.select { |record| codes.include?(record["country_code"].to_s.upcase) }
    end

    def etag
      return "curated-power-plants:missing" unless File.exist?(DATA_FILE)

      stat = File.stat(DATA_FILE)
      "curated-power-plants:#{stat.size}:#{stat.mtime.to_i}"
    end

    private

    def normalize_codes(country_codes)
      Array(country_codes)
        .flat_map { |value| value.to_s.split(",") }
        .map { |code| code.to_s.strip.upcase }
        .reject(&:blank?)
        .uniq
    end
  end
end
