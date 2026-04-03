class TradeLocationRefreshService
  extend Refreshable
  include TabularDatasetLoader

  DEFAULT_SOURCE_PATH = Rails.root.join("tmp", "imports", "trade_locations.csv").freeze
  SOURCE_PATH_ENV = "TRADE_LOCATIONS_SOURCE_PATH".freeze
  SOURCE_URL_ENV = "TRADE_LOCATIONS_SOURCE_URL".freeze
  WORLD_PORT_INDEX_SOURCE_PATH_ENV = "WORLD_PORT_INDEX_SOURCE_PATH".freeze
  WORLD_PORT_INDEX_SOURCE_URL_ENV = "WORLD_PORT_INDEX_SOURCE_URL".freeze
  WORLD_PORT_INDEX_ENABLED_ENV = "WORLD_PORT_INDEX_ENABLED".freeze
  WORLD_PORT_INDEX_SSL_VERIFY_ENV = "WORLD_PORT_INDEX_SSL_VERIFY".freeze
  WORLD_PORT_INDEX_DEFAULT_QUERY_URL = "https://vcps.nga.mil/nauticalpubs-feature/rest/services/WPI/World_Port_Index_Viewer/FeatureServer/0/query".freeze
  WORLD_PORT_INDEX_MIRROR_QUERY_URL = "https://services-eu1.arcgis.com/BuS9rtTsYEV5C0xh/arcgis/rest/services/World_Port_Index/FeatureServer/0/query".freeze
  WORLD_PORT_INDEX_PAGE_SIZE = 2000
  UPSERT_COLUMNS = %i[
    locode
    country_code
    country_code_alpha3
    country_name
    subdivision_code
    name
    normalized_name
    location_kind
    function_codes
    latitude
    longitude
    status
    source
    metadata
    fetched_at
    created_at
    updated_at
  ].freeze
  UNLOCODE_SOURCE_STATUS = {
    provider: "trade_locations",
    display_name: "Trade Locations",
    feed_kind: "trade_locations",
  }.freeze
  WORLD_PORT_INDEX_SOURCE_STATUS = {
    provider: "nga_wpi",
    display_name: "World Port Index",
    feed_kind: "trade_locations",
  }.freeze

  refreshes model: TradeLocation, interval: 7.days, column: :fetched_at

  def refresh
    now = Time.current
    merged_records = {}
    source_count = 0

    if world_port_index_enabled?
      source_count += 1
      fetch_world_port_index(now).each do |record|
        merge_record!(merged_records, record)
      end
    end

    if configured_source_path.present? || configured_source_url.present?
      source_count += 1
      fetch_unlocode(now).each do |record|
        merge_record!(merged_records, record)
      end
    end

    return record_disabled(now) if source_count.zero?

    upsert_records(merged_records.values)
    merged_records.size
  rescue StandardError => e
    Rails.logger.error("TradeLocationRefreshService: #{e.message}")
    0
  end

  private

  def fetch_world_port_index(now)
    attempted_sources = []
    last_error = nil

    world_port_index_sources.each do |source|
      attempted_sources << source.slice(:label, :path, :url)
      rows = world_port_index_rows(path: source[:path], url: source[:url])
      records = rows.filter_map { |row| build_world_port_index_record(row, now, source_variant: source[:label]) }

      SourceFeedStatusRecorder.record(
        **WORLD_PORT_INDEX_SOURCE_STATUS,
        endpoint_url: source[:url].presence || source[:path],
        status: "success",
        records_fetched: rows.size,
        records_stored: records.size,
        metadata: {
          source_kind: source[:path].present? ? "file" : (csv_endpoint?(source[:url]) ? "csv_url" : "feature_service"),
          source_path: source[:path],
          source_url: source[:url],
          source_variant: source[:label],
          attempted_sources: attempted_sources,
          ssl_verify: world_port_index_ssl_verify?,
        },
        occurred_at: now
      )

      return records
    rescue StandardError => e
      last_error = e
      next
    end

    SourceFeedStatusRecorder.record(
      **WORLD_PORT_INDEX_SOURCE_STATUS,
      endpoint_url: configured_world_port_index_source_url.presence || configured_world_port_index_source_path || WORLD_PORT_INDEX_MIRROR_QUERY_URL,
      status: "error",
      error_message: last_error&.message,
      metadata: {
        attempted_sources: attempted_sources,
        ssl_verify: world_port_index_ssl_verify?,
      },
      occurred_at: Time.current
    )
    []
  end

  def fetch_unlocode(now)
    path = configured_source_path
    url = configured_source_url
    rows = csv_rows_from_source(path: path, url: url)
    records = rows.filter_map { |row| build_unlocode_record(row, now) }

    SourceFeedStatusRecorder.record(
      **UNLOCODE_SOURCE_STATUS,
      endpoint_url: url.presence || path,
      status: "success",
      records_fetched: rows.size,
      records_stored: records.size,
      metadata: {
        source_kind: path.present? ? "file" : "csv_url",
        source_path: path,
        source_url: url,
      },
      occurred_at: now
    )

    records
  rescue StandardError => e
    SourceFeedStatusRecorder.record(
      **UNLOCODE_SOURCE_STATUS,
      endpoint_url: configured_source_url.presence || configured_source_path,
      status: "error",
      error_message: e.message,
      occurred_at: Time.current
    )
    []
  end

  def build_unlocode_record(row, now)
    locode = value_for(row, "UNLOCODE")
    country_code = normalize_iso2(value_for(row, "country_iso2", "country_code", "Country"))
    locode = nil unless locode.to_s.length == 5
    locode_suffix = value_for(row, "locode_suffix", "LOCODE", "location_code", "locode")
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

  def build_world_port_index_record(row, now, source_variant:)
    wpi_number = value_for(row, "wpinumber", "WPI Number")
    wpi_number ||= value_for(row, "INDEX_NO")
    locode = normalize_world_port_index_locode(value_for(row, "unlocode", "UN/LOCODE"), wpi_number)
    return if locode.blank?

    name = value_for(row, "main_port_", "Main Port Name", "PORT_NAME", "name") || value_for(row, "alternate_", "Alternate Port Name")
    return if name.blank?

    country_code = normalize_iso2(value_for(row, "countryCode", "COUNTRY", "country_iso2", "Country Code")) || normalize_iso2(locode.to_s[0, 2])
    alpha3 = value_for(row, "country_iso3", "country_code_alpha3")&.upcase || country_reference_for(country_code)[:alpha3]
    country_name = value_for(row, "country_name", "Country Name") || country_reference_for(country_code)[:name]
    lat, lng = coordinates_for(row)
    metadata = world_port_index_metadata(row, source_variant: source_variant, wpi_number: wpi_number)

    {
      locode: locode,
      country_code: country_code,
      country_code_alpha3: alpha3,
      country_name: country_name,
      name: name,
      normalized_name: normalize_name(name),
      location_kind: "port",
      function_codes: "1",
      latitude: lat,
      longitude: lng,
      status: "active",
      source: "nga_wpi#{"+#{source_variant}" if source_variant != "official"}",
      metadata: metadata,
      fetched_at: now,
      created_at: now,
      updated_at: now,
    }.compact
  end

  def upsert_records(records)
    return if records.blank?

    records.each_slice(2000) do |batch|
      TradeLocation.upsert_all(batch.map { |record| normalized_upsert_record(record) }, unique_by: :index_trade_locations_on_locode)
    end
  end

  def normalized_upsert_record(record)
    UPSERT_COLUMNS.each_with_object({}) do |column, memo|
      memo[column] = record[column]
    end
  end

  def configured_source_path
    ENV[SOURCE_PATH_ENV].presence || (DEFAULT_SOURCE_PATH.to_s if File.exist?(DEFAULT_SOURCE_PATH))
  end

  def configured_source_url
    ENV[SOURCE_URL_ENV].presence
  end

  def configured_world_port_index_source_path
    ENV[WORLD_PORT_INDEX_SOURCE_PATH_ENV].presence
  end

  def configured_world_port_index_source_url
    ENV[WORLD_PORT_INDEX_SOURCE_URL_ENV].presence || WORLD_PORT_INDEX_DEFAULT_QUERY_URL
  end

  def world_port_index_sources
    path = configured_world_port_index_source_path
    return [{ label: "file", path: path, url: nil }] if path.present?

    [
      { label: "official", path: nil, url: configured_world_port_index_source_url },
      { label: "mirror", path: nil, url: WORLD_PORT_INDEX_MIRROR_QUERY_URL },
    ].uniq { |source| source[:url].presence || source[:path] }
  end

  def record_disabled(now)
    SourceFeedStatusRecorder.record(
      **UNLOCODE_SOURCE_STATUS,
      status: "disabled",
      metadata: {
        expected_path_env: SOURCE_PATH_ENV,
        expected_url_env: SOURCE_URL_ENV,
        world_port_index_enabled_env: WORLD_PORT_INDEX_ENABLED_ENV,
        world_port_index_source_url_env: WORLD_PORT_INDEX_SOURCE_URL_ENV,
        world_port_index_source_path_env: WORLD_PORT_INDEX_SOURCE_PATH_ENV,
        world_port_index_ssl_verify_env: WORLD_PORT_INDEX_SSL_VERIFY_ENV,
      },
      occurred_at: now
    )
    0
  end

  def world_port_index_enabled?
    !ENV.fetch(WORLD_PORT_INDEX_ENABLED_ENV, "true").match?(/\A(false|0|off|no)\z/i)
  end

  def world_port_index_rows(path:, url:)
    return csv_rows_from_source(path: path) if path.present?
    return csv_rows_from_source(url: url) if csv_endpoint?(url)

    paginated_world_port_index_rows(url)
  end

  def paginated_world_port_index_rows(url)
    rows = []
    offset = 0
    query_url = normalized_query_url(url)

    loop do
      payload = json_payload_from_url(
        query_url,
        {
          where: "1=1",
          outFields: "*",
          returnGeometry: "true",
          f: "json",
          resultOffset: offset,
          resultRecordCount: WORLD_PORT_INDEX_PAGE_SIZE,
        }
      )

      if payload["error"].present?
        raise payload["error"]["message"].to_s.presence || "Invalid World Port Index response"
      end

      features = Array(payload["features"])
      break if features.empty?

      rows.concat(features.map { |feature| flatten_feature_row(feature) })
      offset += features.size
      break unless payload["exceededTransferLimit"] || features.size >= WORLD_PORT_INDEX_PAGE_SIZE
    end

    rows
  end

  def flatten_feature_row(feature)
    attributes = feature["attributes"].is_a?(Hash) ? feature["attributes"] : {}
    geometry = feature["geometry"].is_a?(Hash) ? feature["geometry"] : {}

    attributes.merge(
      "latitude" => geometry["y"],
      "longitude" => geometry["x"]
    )
  end

  def json_payload_from_url(url, params)
    uri = URI(url)
    existing_params = URI.decode_www_form(uri.query.to_s).to_h
    uri.query = URI.encode_www_form(existing_params.merge(params.transform_values(&:to_s)))
    JSON.parse(fetch_remote_body(uri.to_s, verify_ssl: world_port_index_ssl_verify?))
  end

  def normalized_query_url(url)
    token = url.to_s
    return token if token.end_with?("/query")
    return "#{token}/query" if token.match?(%r{/0/?\z})
    return "#{token}/0/query" if token.match?(%r{/FeatureServer/?\z})

    "#{token}/query"
  end

  def csv_endpoint?(url)
    token = url.to_s.downcase
    token.end_with?(".csv", ".csv.gz", ".gz")
  end

  def world_port_index_ssl_verify?
    !ENV.fetch(WORLD_PORT_INDEX_SSL_VERIFY_ENV, "true").match?(/\A(false|0|off|no)\z/i)
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

  def normalize_world_port_index_locode(locode, wpi_number)
    token = locode.to_s.upcase.gsub(/[^A-Z0-9]/, "")
    return token if token.present?

    wpi = wpi_number.to_s.gsub(/\D/, "")
    return if wpi.blank?

    "WPI#{wpi}"
  end

  def world_port_index_metadata(row, source_variant:, wpi_number:)
    harbor_size = value_for(row, "harbor_siz", "Harbor Size")
    harbor_use = value_for(row, "harbor_use", "Harbor Use")
    world_water = value_for(row, "dodwaterbo", "World Water Body")
    cargo_depth = numeric_value_for(row, "cargo_pier", "Cargo Pier Depth (m)")
    oil_depth = numeric_value_for(row, "oil_termin", "Oil Terminal Depth (m)")
    lng_depth = numeric_value_for(row, "lng_termin", "Liquified Natural Gas Terminal Depth (m)")
    flow_types = inferred_wpi_flow_types(harbor_use: harbor_use, world_water: world_water, cargo_depth: cargo_depth, oil_depth: oil_depth, lng_depth: lng_depth)

    {
      "wpi_number" => wpi_number,
      "alternate_name" => value_for(row, "alternate_", "Alternate Port Name"),
      "source_variant" => source_variant,
      "world_water_body" => world_water,
      "harbor_size" => harbor_size,
      "harbor_type" => value_for(row, "harbor_typ", "Harbor Type"),
      "harbor_use" => harbor_use,
      "channel_depth_m" => numeric_value_for(row, "channel_de", "Channel Depth (m)"),
      "anchorage_depth_m" => numeric_value_for(row, "anchorage_", "Anchorage Depth (m)"),
      "cargo_pier_depth_m" => cargo_depth,
      "oil_terminal_depth_m" => oil_depth,
      "lng_terminal_depth_m" => lng_depth,
      "max_vessel_length_m" => numeric_value_for(row, "maxvessell", "Maximum Vessel Length (m)"),
      "max_vessel_beam_m" => numeric_value_for(row, "maxvesselb", "Maximum Vessel Beam (m)"),
      "max_vessel_draft_m" => numeric_value_for(row, "maxvesseld", "Maximum Vessel Draft (m)"),
      "port_security" => value_for(row, "port_secur", "Port Security"),
      "flow_types" => flow_types,
      "commodity_keys" => SupplyChainCatalog.commodity_keys_for_flow_types(flow_types),
      "importance" => world_port_index_importance_score(row, harbor_size: harbor_size, cargo_depth: cargo_depth, oil_depth: oil_depth, lng_depth: lng_depth),
    }.compact
  end

  def inferred_wpi_flow_types(harbor_use:, world_water:, cargo_depth:, oil_depth:, lng_depth:)
    flow_types = []

    flow_types.concat(%w[trade container]) if harbor_use.to_s.downcase.include?("cargo") || cargo_depth.to_f.positive?
    flow_types << "oil" if oil_depth.to_f.positive?
    flow_types << "lng" if lng_depth.to_f.positive?

    water = world_water.to_s.downcase
    flow_types << "atlantic" if water.include?("atlantic")
    flow_types << "pacific" if water.include?("pacific")
    flow_types << "indian_ocean" if water.include?("indian")
    flow_types << "gulf" if water.include?("gulf")
    flow_types << "mediterranean" if water.include?("mediterranean")

    flow_types.uniq
  end

  def world_port_index_importance_score(row, harbor_size:, cargo_depth:, oil_depth:, lng_depth:)
    score = case harbor_size.to_s.downcase
    when "large" then 0.84
    when "medium" then 0.72
    when "small" then 0.58
    when "very small" then 0.44
    else 0.52
    end

    score += 0.08 if cargo_depth.to_f >= 10
    score += 0.08 if oil_depth.to_f.positive?
    score += 0.08 if lng_depth.to_f.positive?
    score += 0.05 if numeric_value_for(row, "maxvesseld", "Maximum Vessel Draft (m)").to_f >= 12
    score.clamp(0.25, 0.99).round(3)
  end

  def value_for(row, *keys)
    lookup = normalized_row_lookup(row)
    keys.each do |key|
      value = row[key]
      return value.to_s.strip if value.present?
      normalized = lookup[normalized_lookup_key(key)]
      return normalized.to_s.strip if normalized.present?
    end
    nil
  end

  def numeric_value_for(row, *keys)
    value = value_for(row, *keys)
    return if value.blank?

    Float(value)
  rescue ArgumentError, TypeError
    nil
  end

  def normalized_row_lookup(row)
    @normalized_row_lookup ||= {}
    @normalized_row_lookup[row.object_id] ||= row.to_h.each_with_object({}) do |(key, value), memo|
      memo[normalized_lookup_key(key)] = value
    end
  end

  def normalized_lookup_key(key)
    key.to_s.downcase.gsub(/[^a-z0-9]/, "")
  end

  def normalize_iso2(value)
    code = value.to_s.upcase
    code.match?(/\A[A-Z]{2}\z/) ? code : nil
  end

  def country_reference_for(country_code)
    return {} if country_code.blank?

    country_reference_by_iso2[country_code.to_s.upcase] || {}
  end

  def country_reference_by_iso2
    @country_reference_by_iso2 ||= begin
      refs = {}

      CountryProfile.where.not(country_code: nil).find_each do |profile|
        refs[profile.country_code.to_s.upcase] ||= {
          alpha3: profile.country_code_alpha3,
          name: profile.country_name,
        }
      end

      CountryIndicatorSnapshot.where.not(country_code: nil).find_each do |snapshot|
        refs[snapshot.country_code.to_s.upcase] ||= {
          alpha3: snapshot.country_code_alpha3,
          name: snapshot.country_name,
        }
      end

      refs
    end
  end

  def merge_record!(index, record)
    return if record.blank?

    key = record.fetch(:locode)
    index[key] = if index[key].present?
      merge_records(index[key], record)
    else
      record
    end
  end

  def merge_records(existing, incoming)
    {
      locode: existing[:locode] || incoming[:locode],
      country_code: existing[:country_code] || incoming[:country_code],
      country_code_alpha3: existing[:country_code_alpha3] || incoming[:country_code_alpha3],
      country_name: existing[:country_name] || incoming[:country_name],
      subdivision_code: existing[:subdivision_code] || incoming[:subdivision_code],
      name: existing[:name] || incoming[:name],
      normalized_name: existing[:normalized_name] || incoming[:normalized_name],
      location_kind: existing[:location_kind] == "port" ? existing[:location_kind] : (incoming[:location_kind] || existing[:location_kind]),
      function_codes: existing[:function_codes] || incoming[:function_codes],
      latitude: existing[:latitude] || incoming[:latitude],
      longitude: existing[:longitude] || incoming[:longitude],
      status: existing[:status] == "active" ? existing[:status] : (incoming[:status] || existing[:status]),
      source: [existing[:source], incoming[:source]].compact.uniq.join("+"),
      metadata: (existing[:metadata].is_a?(Hash) ? existing[:metadata] : {}).merge(
        incoming[:metadata].is_a?(Hash) ? incoming[:metadata] : {}
      ),
      fetched_at: [existing[:fetched_at], incoming[:fetched_at]].compact.max,
      created_at: existing[:created_at] || incoming[:created_at],
      updated_at: [existing[:updated_at], incoming[:updated_at]].compact.max,
    }.compact
  end
end
