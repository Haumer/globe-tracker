class DataSourceRegistry
  DATA_FILE = Rails.root.join("db", "data", "source_registry.json").freeze
  STATUS_PRIORITY = {
    "active" => 0,
    "seed" => 1,
    "planned" => 2,
    "deprecated" => 3,
  }.freeze

  class << self
    def all
      return [] unless File.exist?(DATA_FILE)

      payload = JSON.parse(File.read(DATA_FILE))
      records = Array(payload["sources"] || payload)

      records
        .select { |record| record.is_a?(Hash) }
        .sort_by do |record|
          [
            STATUS_PRIORITY.fetch(record["status"].to_s.downcase, 9),
            record["priority"].to_i,
            record["name"].to_s,
          ]
        end
    rescue JSON::ParserError => error
      Rails.logger.error("DataSourceRegistry parse failed: #{error.message}")
      []
    end

    def filtered(country_codes: nil, region_key: nil, statuses: nil, target_models: nil)
      records = all

      if region_key.present?
        keys = normalize_values(region_key).map(&:downcase)
        records = records.select do |record|
          (Array(record["region_keys"]).map { |value| value.to_s.downcase } & keys).any?
        end
      end

      if country_codes.present?
        codes = normalize_values(country_codes).map(&:upcase)
        records = records.select do |record|
          (Array(record["country_codes"]).map { |value| value.to_s.upcase } & codes).any?
        end
      end

      if statuses.present?
        allowed = normalize_values(statuses).map(&:downcase)
        records = records.select { |record| allowed.include?(record["status"].to_s.downcase) }
      end

      if target_models.present?
        allowed = normalize_values(target_models).map(&:downcase)
        records = records.select { |record| allowed.include?(record["target_model"].to_s.downcase) }
      end

      records
    end

    def etag
      return "data-source-registry:missing" unless File.exist?(DATA_FILE)

      stat = File.stat(DATA_FILE)
      "data-source-registry:#{stat.size}:#{stat.mtime.to_i}"
    end

    private

    def normalize_values(value)
      Array(value)
        .flat_map { |item| item.to_s.split(",") }
        .map { |item| item.to_s.strip }
        .reject(&:blank?)
        .uniq
    end
  end
end
