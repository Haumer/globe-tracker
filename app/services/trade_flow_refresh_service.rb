class TradeFlowRefreshService
  extend Refreshable
  include TabularDatasetLoader

  DEFAULT_SOURCE_PATH = Rails.root.join("tmp", "imports", "strategic_trade_flows.csv.gz").freeze
  SOURCE_PATH_ENV = "STRATEGIC_TRADE_FLOWS_SOURCE_PATH".freeze
  SOURCE_URL_ENV = "STRATEGIC_TRADE_FLOWS_SOURCE_URL".freeze
  SOURCE_STATUS = {
    provider: "strategic_trade_flows",
    display_name: "Strategic Trade Flows",
    feed_kind: "trade_flows",
  }.freeze

  refreshes model: TradeFlowSnapshot, interval: 24.hours, column: :fetched_at

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
        strategic_commodity_keys: SupplyChainCatalog::STRATEGIC_COMMODITIES.keys,
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
    Rails.logger.error("TradeFlowRefreshService: #{e.message}")
    0
  end

  private

  def build_record(row, now)
    hs_code = value_for(row, "hs_code", "product_code", "commodity_code")
    commodity_key = value_for(row, "commodity_key") || SupplyChainCatalog.commodity_key_for_hs(hs_code)
    return if commodity_key.blank?

    period_start, period_end, period_type = period_bounds(row)
    return if period_start.blank?

    reporter_alpha3 = value_for(row, "reporter_iso3", "reporter_country_code_alpha3")
    partner_alpha3 = value_for(row, "partner_iso3", "partner_country_code_alpha3")
    return if reporter_alpha3.blank? || partner_alpha3.blank?

    {
      reporter_country_code: normalize_iso2(value_for(row, "reporter_iso2", "reporter_country_code")),
      reporter_country_code_alpha3: reporter_alpha3.upcase,
      reporter_country_name: value_for(row, "reporter_name", "reporter_country_name"),
      partner_country_code: normalize_iso2(value_for(row, "partner_iso2", "partner_country_code")),
      partner_country_code_alpha3: partner_alpha3.upcase,
      partner_country_name: value_for(row, "partner_name", "partner_country_name"),
      flow_direction: normalized_flow_direction(row),
      commodity_key: commodity_key,
      commodity_name: value_for(row, "commodity_name") || SupplyChainCatalog.commodity_name_for(commodity_key),
      hs_code: hs_code.presence,
      period_type: period_type,
      period_start: period_start,
      period_end: period_end,
      trade_value_usd: decimal_for(row, "trade_value_usd", "value_usd", "trade_value"),
      quantity: decimal_for(row, "quantity", "qty"),
      quantity_unit: value_for(row, "quantity_unit", "qty_unit"),
      source: value_for(row, "source") || "trade_flows",
      dataset: value_for(row, "dataset") || "normalized_trade_flows",
      release_version: value_for(row, "release_version"),
      raw_payload: row.to_h,
      fetched_at: now,
      created_at: now,
      updated_at: now,
    }
  end

  def upsert_records(records)
    return if records.blank?

    records.each_slice(1000) do |batch|
      TradeFlowSnapshot.upsert_all(batch, unique_by: :idx_trade_flow_snapshots_unique_period)
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
      endpoint_url: nil,
      status: "disabled",
      metadata: {
        expected_path_env: SOURCE_PATH_ENV,
        expected_url_env: SOURCE_URL_ENV,
      },
      occurred_at: now
    )
    0
  end

  def normalized_flow_direction(row)
    direction = value_for(row, "flow_direction", "direction").to_s.downcase
    return "import" if direction.blank?
    return "export" if direction.include?("export")
    return "import" if direction.include?("import")

    direction
  end

  def period_bounds(row)
    if (date_value = value_for(row, "period_start", "date", "period"))
      parsed = parse_period_start(date_value)
      period_type = infer_period_type(date_value, row)
      return [parsed, parse_period_end(value_for(row, "period_end"), parsed, period_type), period_type]
    end

    year = integer_for(row, "year", "period_year")
    return if year.blank? || year <= 0

    start = Date.new(year, 1, 1)
    [start, start.end_of_year, "year"]
  end

  def parse_period_start(value)
    token = value.to_s.strip
    return if token.blank?

    if token.match?(/\A\d{4}-\d{2}\z/)
      Date.strptime("#{token}-01", "%Y-%m-%d")
    elsif token.match?(/\A\d{4}\z/)
      Date.new(token.to_i, 1, 1)
    else
      Date.parse(token)
    end
  rescue Date::Error
    nil
  end

  def parse_period_end(value, start_date, period_type)
    parsed = parse_period_start(value)
    return parsed if parsed.present?
    return start_date.end_of_month if period_type == "month"

    start_date&.end_of_year
  end

  def infer_period_type(token, row)
    explicit = value_for(row, "period_type")
    return explicit if explicit.present?

    value = token.to_s.strip
    return "month" if value.match?(/\A\d{4}-\d{2}\z/)
    return "year" if value.match?(/\A\d{4}\z/)

    "date"
  end

  def value_for(row, *keys)
    keys.each do |key|
      value = row[key]
      return value.to_s.strip if value.present?
    end
    nil
  end

  def integer_for(row, *keys)
    value = value_for(row, *keys)
    return if value.blank?

    value.to_i
  end

  def decimal_for(row, *keys)
    value = value_for(row, *keys)
    return if value.blank?

    value.to_d
  end

  def normalize_iso2(value)
    code = value.to_s.upcase
    code.match?(/\A[A-Z]{2}\z/) ? code : nil
  end
end
