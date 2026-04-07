require "csv"

class CommoditySiteImportService
  SOURCE_DIR = Rails.root.join("db", "data", "commodity_site_sources").freeze
  MANIFEST_FILE = SOURCE_DIR.join("manifest.json").freeze
  OUTPUT_FILE = Rails.root.join("db", "data", "commodity_sites.json").freeze

  REQUIRED_FIELDS = %w[
    id
    name
    commodity_key
    commodity_name
    site_kind
    stage
    country_code
    country_name
    location_label
    lat
    lng
    source_name
    source_url
    source_kind
  ].freeze

  def self.import!(manifest_path: MANIFEST_FILE, output_path: OUTPUT_FILE)
    new(manifest_path:, output_path:).import!
  end

  def initialize(manifest_path:, output_path:)
    @manifest_path = Pathname(manifest_path)
    @output_path = Pathname(output_path)
  end

  def import!
    manifest = load_manifest
    entries = Array(manifest.fetch("sources"))
    raise ArgumentError, "Commodity site manifest has no sources" if entries.empty?

    merged = {}

    entries.each do |source_entry|
      load_source_records(source_entry).each do |record|
        normalized = normalize_record(record, source_entry)
        existing = merged[normalized.fetch("id")]
        next if existing && existing.fetch("_priority") > normalized.fetch("_priority")

        merged[normalized.fetch("id")] = normalized
      end
    end

    final_records = merged.values
      .sort_by { |record| [record.fetch("commodity_key"), record.fetch("country_name"), record.fetch("name")] }
      .map { |record| record.except("_priority") }

    FileUtils.mkdir_p(@output_path.dirname)
    File.write(@output_path, JSON.pretty_generate(final_records) + "\n")

    {
      count: final_records.size,
      source_count: entries.size,
      commodity_counts: final_records.group_by { |record| record.fetch("commodity_key") }.transform_values(&:size)
    }
  end

  private

  def load_manifest
    JSON.parse(File.read(@manifest_path))
  rescue Errno::ENOENT
    raise ArgumentError, "Commodity site manifest not found at #{@manifest_path}"
  rescue JSON::ParserError => error
    raise ArgumentError, "Commodity site manifest invalid JSON: #{error.message}"
  end

  def load_source_records(source_entry)
    source_type = source_entry.fetch("type")
    path = resolve_path(source_entry.fetch("path"))

    case source_type
    when "normalized_json"
      JSON.parse(File.read(path))
    when "normalized_csv"
      CSV.read(path, headers: true).map(&:to_h)
    else
      raise ArgumentError, "Unsupported commodity site source type: #{source_type}"
    end
  rescue Errno::ENOENT
    raise ArgumentError, "Commodity site source missing: #{path}"
  rescue JSON::ParserError => error
    raise ArgumentError, "Commodity site source invalid JSON (#{path}): #{error.message}"
  end

  def resolve_path(path)
    pathname = Pathname(path)
    pathname.absolute? ? pathname : @manifest_path.dirname.join(pathname)
  end

  def normalize_record(raw_record, source_entry)
    record = raw_record.deep_dup
    priority = source_entry.fetch("priority", 100).to_i

    normalized = {
      "id" => normalize_string(record["id"]),
      "name" => normalize_string(record["name"]),
      "map_label" => normalize_string(record["map_label"]),
      "commodity_key" => normalize_key(record["commodity_key"]),
      "commodity_name" => normalize_string(record["commodity_name"]),
      "site_kind" => normalize_key(record["site_kind"]),
      "stage" => normalize_key(record["stage"]),
      "country_code" => normalize_string(record["country_code"])&.upcase,
      "country_name" => normalize_string(record["country_name"]),
      "location_label" => normalize_string(record["location_label"]),
      "location_precision" => normalize_string(record["location_precision"]),
      "lat" => normalize_float(record["lat"]),
      "lng" => normalize_float(record["lng"]),
      "operator" => normalize_string(record["operator"]),
      "products" => normalize_products(record["products"]),
      "summary" => normalize_string(record["summary"]),
      "source_name" => normalize_string(record["source_name"]),
      "source_url" => normalize_string(record["source_url"]),
      "source_kind" => normalize_key(record["source_kind"]),
      "source_dataset" => normalize_string(record["source_dataset"]) || normalize_string(source_entry["key"]),
      "_priority" => priority
    }.compact

    normalized["map_label"] ||= default_map_label(normalized["name"])
    normalized["location_precision"] ||= "approximate placement"

    missing = REQUIRED_FIELDS.reject { |field| present_field?(normalized[field]) }
    raise ArgumentError, "Commodity site record #{normalized["id"] || "(missing id)"} missing #{missing.join(', ')}" if missing.any?

    normalized
  end

  def normalize_string(value)
    text = value.is_a?(String) ? value.strip : value
    text.present? ? text.to_s : nil
  end

  def normalize_key(value)
    normalize_string(value)&.tr(" ", "_")&.downcase
  end

  def normalize_float(value)
    return value if value.is_a?(Numeric)

    text = normalize_string(value)
    return nil if text.blank?

    Float(text)
  rescue ArgumentError
    nil
  end

  def normalize_products(value)
    items =
      case value
      when Array then value
      when String then value.split("|")
      else []
      end

    cleaned = items.filter_map { |item| normalize_string(item) }
    cleaned.presence
  end

  def present_field?(value)
    value.is_a?(Array) ? value.any? : value.present?
  end

  def default_map_label(name)
    return nil if name.blank?

    words = name.split(/\s+/).first(2)
    label = words.join(" ")
    label.length > 18 ? "#{label[0, 18]}…" : label
  end
end
