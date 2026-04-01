class EnergyBalanceRefreshService
  extend Refreshable
  include TabularDatasetLoader

  DEFAULT_SOURCE_PATH = Rails.root.join("tmp", "imports", "energy_balances.csv.gz").freeze
  SOURCE_PATH_ENV = "ENERGY_BALANCES_SOURCE_PATH".freeze
  SOURCE_URL_ENV = "ENERGY_BALANCES_SOURCE_URL".freeze
  SOURCE_STATUS = {
    provider: "energy_balances",
    display_name: "Energy Balances",
    feed_kind: "energy_balances",
  }.freeze

  refreshes model: EnergyBalanceSnapshot, interval: 24.hours, column: :fetched_at

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
    Rails.logger.error("EnergyBalanceRefreshService: #{e.message}")
    0
  end

  private

  def build_record(row, now)
    country_alpha3 = value_for(row, "country_iso3", "country_code_alpha3")
    commodity_key = value_for(row, "commodity_key")
    metric_key = value_for(row, "metric_key")
    period_start = parse_period_start(value_for(row, "period_start", "period", "date"))
    return if country_alpha3.blank? || commodity_key.blank? || metric_key.blank? || period_start.blank?

    period_type = value_for(row, "period_type") || infer_period_type(value_for(row, "period_start", "period", "date"))

    {
      country_code: normalize_iso2(value_for(row, "country_iso2", "country_code")),
      country_code_alpha3: country_alpha3.upcase,
      country_name: value_for(row, "country_name") || country_alpha3.upcase,
      commodity_key: commodity_key,
      metric_key: metric_key,
      period_type: period_type,
      period_start: period_start,
      period_end: parse_period_end(value_for(row, "period_end"), period_start, period_type),
      value_numeric: decimal_for(row, "value_numeric", "value"),
      unit: value_for(row, "unit"),
      source: value_for(row, "source") || "energy_balances",
      dataset: value_for(row, "dataset") || "normalized_energy_balances",
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
      EnergyBalanceSnapshot.upsert_all(batch, unique_by: :idx_energy_balance_snapshots_unique_period)
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
    explicit = parse_period_start(value)
    return explicit if explicit.present?

    period_type == "month" ? start_date.end_of_month : start_date.end_of_year
  end

  def infer_period_type(token)
    value = token.to_s
    return "month" if value.match?(/\A\d{4}-\d{2}(-\d{2})?\z/)
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
