class RegionalDistrictBoundaryCatalog
  SOURCES_DIR = Rails.root.join("db", "data", "regional_district_boundary_sources").freeze
  MANIFEST_FILE = SOURCES_DIR.join("manifest.json").freeze

  class << self
    def feature_collection(country_codes: nil)
      features = all_features(country_codes: country_codes)

      {
        "type" => "FeatureCollection",
        "metadata" => {
          "source_count" => manifest_sources.length,
          "feature_count" => features.length
        },
        "features" => features
      }
    end

    def all_features(country_codes: nil)
      codes = normalize_codes(country_codes)
      manifest_sources.flat_map do |source|
        source_path = SOURCES_DIR.join(source["path"].to_s)
        next [] unless File.exist?(source_path)

        payload = JSON.parse(File.read(source_path))
        features = Array(payload["features"])
        if codes.present?
          features.select! do |feature|
            feature_codes = [
              feature.dig("properties", "country_code"),
              feature.dig("properties", "country_code_alpha3")
            ].map { |value| value.to_s.upcase }.reject(&:blank?)

            (feature_codes & codes).any?
          end
        end

        features
      rescue JSON::ParserError => error
        Rails.logger.warn("RegionalDistrictBoundaryCatalog parse failed for #{source_path}: #{error.message}")
        []
      end
    end

    def etag(country_codes: nil)
      codes = normalize_codes(country_codes).join(",")
      fingerprint = source_files.filter_map do |path|
        next unless File.exist?(path)

        stat = File.stat(path)
        "#{File.basename(path)}:#{stat.size}:#{stat.mtime.to_i}"
      end.join(":")

      "regional-district-boundaries:#{codes}:#{fingerprint.presence || 'missing'}"
    end

    private

    def manifest_sources
      return [] unless File.exist?(MANIFEST_FILE)

      manifest = JSON.parse(File.read(MANIFEST_FILE))
      Array(manifest["sources"])
    rescue JSON::ParserError => error
      Rails.logger.warn("RegionalDistrictBoundaryCatalog manifest parse failed: #{error.message}")
      []
    end

    def source_files
      [MANIFEST_FILE, *manifest_sources.map { |source| SOURCES_DIR.join(source["path"].to_s) }]
    end

    def normalize_codes(country_codes)
      Array(country_codes)
        .flat_map { |value| value.to_s.split(",") }
        .map { |value| value.to_s.strip.upcase }
        .reject(&:blank?)
        .uniq
    end
  end
end
