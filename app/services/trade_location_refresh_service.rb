class TradeLocationRefreshService
  extend Refreshable
  include TabularDatasetLoader

  DEFAULT_SOURCE_PATH = Rails.root.join("tmp", "imports", "trade_locations.csv").freeze
  SOURCE_PATH_ENV = "TRADE_LOCATIONS_SOURCE_PATH".freeze
  SOURCE_URL_ENV = "TRADE_LOCATIONS_SOURCE_URL".freeze
  SOURCE_STATUS = {
    provider: "trade_locations",
    display_name: "Trade Locations",
    feed_kind: "trade_locations",
  }.freeze

  refreshes model: TradeLocation, interval: 7.days, column: :fetched_at

  def refresh
    now = Time.current
    path = configured_source_path
    url = configured_source_url
    return record_disabled(now) if path.blank? && url.blank?

    rows = csv_rows_from_source(path: path, url: url)
    records = rows.filter_map { |row| build_record(row, now) }
    upsert_records(records)

    SourceFeedStatusRecorder.record(
      **SOURCE_STATUS,
      endpoint_url: url.presence || path,
      status: "success",
      records_fetched: rows.size,
      records_stored: records.size,
      metadata: {
        source_path: path,
        source_url: url,
      },
      occurred_at: now
    )

    records.size
  rescue StandardError => e
    SourceFeedStatusRecorder.record(
      **SOURCE_STATUS,
      endpoint_url: configured_source_url.presence || configured_source_path,
      status: "error",
      error_message: e.message,
      occurred_at: Time.current
    )
    Rails.logger.error("TradeLocationRefreshService: #{e.message}")
    0
  end

  private

  def build_record(row, now)
    locode = value_for(row, "locode", "UNLOCODE")
    country_code = normalize_iso2(value_for(row, "country_iso2", "country_code", "Country"))
    locode_suffix = value_for(row, "locode_suffix", "LOCODE", "location_code")
    locode ||= locode_suffix if locode_suffix.to_s.length == 5
    locode ||= [country_code, locode_suffix].compact.join if country_code.present? && locode_suffix.present?
    country_code ||= normalize_iso2(locode.to_s[0, 2]) if locode.present?
    return if locode.blank?

    name = value_for(row, "name", "Name")
    return if name.blank?

    lat, lng = coordinates_for(row)
    function_codes = value_for(row, "function_codes", "Function")

    {
      locode: locode.upcase,
      country_code: country_code,
      country_code_alpha3: value_for(row, "country_iso3", "country_code_alpha3")&.upcase,
      country_name: value_for(row, "country_name"),
      subdivision_code: value_for(row, "subdivision_code", "SubDiv"),
      name: name,
      normalized_name: normalize_name(name),
      location_kind: value_for(row, "location_kind") || infer_location_kind(function_codes),
      function_codes: function_codes,
      latitude: lat,
      longitude: lng,
      status: inferred_status(row),
      source: value_for(row, "source") || "unece_unlocode",
      metadata: row.to_h,
      fetched_at: now,
      created_at: now,
      updated_at: now,
    }
  end

  def upsert_records(records)
    return if records.blank?

    records.each_slice(2000) do |batch|
      TradeLocation.upsert_all(batch, unique_by: :index_trade_locations_on_locode)
    end
  end

  def configured_source_path
    ENV[SOURCE_PATH_ENV].presence || (DEFAULT_SOURCE_PATH.to_s if File.exist?(DEFAULT_SOURCE_PATH))
  end

  def configured_source_url
    ENV[SOURCE_URL_ENV].presence
  end

  def record_disabled(now)
    SourceFeedStatusRecorder.record(
      **SOURCE_STATUS,
      status: "disabled",
      metadata: {
        expected_path_env: SOURCE_PATH_ENV,
        expected_url_env: SOURCE_URL_ENV,
      },
      occurred_at: now
    )
    0
  end

  def coordinates_for(row)
    lat = value_for(row, "latitude")
    lng = value_for(row, "longitude")
    return [lat.to_f, lng.to_f] if lat.present? && lng.present?

    parse_unlocode_coordinates(value_for(row, "coordinates", "Coordinates"))
  end

  def parse_unlocode_coordinates(value)
    token = value.to_s.strip
    return [nil, nil] if token.blank?

    match = token.match(/\A(\d{4})([NS])\s*(\d{5})([EW])\z/)
    return [nil, nil] unless match

    lat_digits, lat_dir, lng_digits, lng_dir = match.captures
    [coord_from_digits(lat_digits, lat_dir), coord_from_digits(lng_digits, lng_dir)]
  end

  def coord_from_digits(digits, direction)
    degrees = digits[0...-2].to_i
    minutes = digits[-2, 2].to_i
    value = degrees + (minutes / 60.0)
    %w[S W].include?(direction) ? -value : value
  end

  def inferred_status(row)
    explicit = value_for(row, "status", "Status")
    return explicit.downcase if explicit.present?

    change_marker = value_for(row, "change_marker", "Ch")
    return "inactive" if change_marker.to_s.upcase.include?("X")

    "active"
  end

  def infer_location_kind(function_codes)
    token = function_codes.to_s
    return "port" if token.include?("1")
    return "inland_terminal" if token.include?("2") || token.include?("3")
    return "airport" if token.include?("4")

    "trade_node"
  end

  def normalize_name(value)
    value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squish
  end

  def value_for(row, *keys)
    keys.each do |key|
      value = row[key]
      return value.to_s.strip if value.present?
    end
    nil
  end

  def normalize_iso2(value)
    code = value.to_s.upcase
    code.match?(/\A[A-Z]{2}\z/) ? code : nil
  end
end
