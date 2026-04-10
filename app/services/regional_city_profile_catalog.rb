require "set"

class RegionalCityProfileCatalog
  SOURCES_DIR = Rails.root.join("db", "data", "city_profile_sources").freeze
  MANIFEST_FILE = SOURCES_DIR.join("manifest.json").freeze
  LEGACY_DATA_FILE = Rails.root.join("db", "data", "city_profiles.json").freeze

  class << self
    def all
      if File.exist?(MANIFEST_FILE)
        load_manifest_records
      elsif File.exist?(LEGACY_DATA_FILE)
        JSON.parse(File.read(LEGACY_DATA_FILE))
      else
        []
      end
    rescue JSON::ParserError => error
      Rails.logger.error("RegionalCityProfileCatalog parse failed: #{error.message}")
      []
    end

    def filtered(country_codes: nil)
      records = all
      return records if country_codes.blank?

      codes = normalize_codes(country_codes)
      records.select { |record| codes.include?(record["country_code"].to_s.upcase) }
    end

    def etag
      files = source_files
      return "regional-city-profiles:missing" if files.blank?

      fingerprint = files.filter_map do |path|
        next unless File.exist?(path)

        stat = File.stat(path)
        "#{File.basename(path)}:#{stat.size}:#{stat.mtime.to_i}"
      end
      return "regional-city-profiles:missing" if fingerprint.blank?

      "regional-city-profiles:#{fingerprint.join(":")}"
    end

    private

    def load_manifest_records
      manifest = JSON.parse(File.read(MANIFEST_FILE))
      sources = Array(manifest["sources"])
      seen_ids = Set.new

      sources.sort_by { |source| source["priority"].to_i }.flat_map do |source|
        source_path = SOURCES_DIR.join(source["path"].to_s)
        next [] unless File.exist?(source_path)

        Array(JSON.parse(File.read(source_path))).filter_map do |record|
          next unless record.is_a?(Hash)

          normalized = record.deep_dup
          normalized["source_pack"] ||= source["key"]
          normalized["priority"] = normalized["priority"].to_i if normalized.key?("priority")

          record_id = normalized["id"].presence
          next if record_id.present? && seen_ids.include?(record_id)

          seen_ids << record_id if record_id.present?
          normalized
        end
      end
    end

    def source_files
      if File.exist?(MANIFEST_FILE)
        manifest = JSON.parse(File.read(MANIFEST_FILE)) rescue {}
        sources = Array(manifest["sources"]).map { |source| SOURCES_DIR.join(source["path"].to_s) }
        [MANIFEST_FILE, *sources]
      elsif File.exist?(LEGACY_DATA_FILE)
        [LEGACY_DATA_FILE]
      else
        []
      end
    end

    def normalize_codes(country_codes)
      Array(country_codes)
        .flat_map { |value| value.to_s.split(",") }
        .map { |code| code.to_s.strip.upcase }
        .reject(&:blank?)
        .uniq
    end
  end
end
