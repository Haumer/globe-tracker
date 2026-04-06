class EnergyBalanceRefreshService
  extend Refreshable
  include TabularDatasetLoader

  DEFAULT_SOURCE_PATH = Rails.root.join("tmp", "imports", "energy_balances.csv.gz").freeze
  SOURCE_PATH_ENV = "ENERGY_BALANCES_SOURCE_PATH".freeze
  SOURCE_URL_ENV = "ENERGY_BALANCES_SOURCE_URL".freeze
  DEFAULT_JODI_OIL_SOURCE_URL_TEMPLATE = "https://www.jodidata.org/_resources/files/downloads/oil-data/annual-csv/primary/primaryyear%<year>d.csv".freeze
  DEFAULT_JODI_OIL_LOOKBACK_YEARS = 1
  JODI_PRIMARY_PRODUCT = "TOTCRUDE".freeze
  JODI_COMPONENT_PRODUCTS = %w[CRUDEOIL NGL OTHERCRUDE].freeze
  JODI_SUPPORTED_PRODUCTS = ([JODI_PRIMARY_PRODUCT] + JODI_COMPONENT_PRODUCTS).freeze
  JODI_UNIT_CONVBBL = "CONVBBL".freeze
  JODI_UNIT_KBD = "KBD".freeze
  JODI_DIRECT_METRICS = {
    ["CLOSTLV", JODI_UNIT_CONVBBL] => { metric_key: "closing_stock_convbbl", unit: "convbbl" },
    ["TOTIMPSB", JODI_UNIT_KBD] => { metric_key: "imports_kbd", unit: "kbd" },
    ["TOTEXPSB", JODI_UNIT_KBD] => { metric_key: "exports_kbd", unit: "kbd" },
    ["INDPROD", JODI_UNIT_KBD] => { metric_key: "indigenous_production_kbd", unit: "kbd" },
    ["DIRECUSE", JODI_UNIT_KBD] => { metric_key: "direct_use_kbd", unit: "kbd" },
    ["REFINOBS", JODI_UNIT_KBD] => { metric_key: "refinery_observed_kbd", unit: "kbd" },
    ["STOCKCH", JODI_UNIT_KBD] => { metric_key: "stock_change_kbd", unit: "kbd" },
  }.freeze
  JODI_SOURCE = "jodi_oil".freeze
  JODI_DATASET = "jodi_oil_primary".freeze
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
    return refresh_from_default_jodi_oil(now) if path.blank? && url.blank?

    refresh_from_configured_source(now, path: path, url: url)
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

  def refresh_from_configured_source(now, path:, url:)
    rows = csv_rows_from_source(path: path, url: url)
    records = build_records_from_rows(rows, now: now, source_url: url, source_path: path)
    upsert_records(records)

    SourceFeedStatusRecorder.record(
      **SOURCE_STATUS,
      endpoint_url: url.presence || path,
      status: "success",
      records_fetched: rows.size,
      records_stored: records.size,
      metadata: {
        source_mode: jodi_oil_rows?(rows) ? "jodi_oil_raw" : "normalized_csv",
        source_path: path,
        source_url: url,
      },
      occurred_at: now
    )

    records.size
  end

  def refresh_from_default_jodi_oil(now)
    body, url, release_version = fetch_default_jodi_oil_source(now)
    rows = CSV.parse(decoded_text(body, url: url), headers: true, liberal_parsing: true)
    records = build_records_from_rows(rows, now: now, source_url: url, release_version: release_version)
    upsert_records(records)

    SourceFeedStatusRecorder.record(
      **SOURCE_STATUS,
      endpoint_url: url,
      status: "success",
      records_fetched: rows.size,
      records_stored: records.size,
      metadata: {
        source_mode: "jodi_oil_default",
        source_url: url,
        release_version: release_version,
        candidate_urls: default_jodi_oil_candidate_urls(now),
      },
      occurred_at: now
    )

    records.size
  end

  def build_records_from_rows(rows, now:, source_url: nil, source_path: nil, release_version: nil)
    return build_records_from_jodi_oil(rows, now: now, source_url: source_url, release_version: release_version) if jodi_oil_rows?(rows)

    rows.filter_map { |row| build_record(row, now) }
  end

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

  def jodi_oil_rows?(rows)
    headers = Array(rows&.headers).map(&:to_s)
    headers.include?("REF_AREA") && headers.include?("TIME_PERIOD") && headers.include?("FLOW_BREAKDOWN")
  end

  def build_records_from_jodi_oil(rows, now:, source_url:, release_version:)
    grouped_rows = Hash.new { |hash, key| hash[key] = Hash.new { |flow_hash, flow_key| flow_hash[flow_key] = [] } }

    rows.each do |row|
      country_code = normalize_iso2(row["REF_AREA"])
      period_start = parse_period_start(row["TIME_PERIOD"])
      product = row["ENERGY_PRODUCT"].to_s.upcase
      flow_breakdown = row["FLOW_BREAKDOWN"].to_s.upcase
      unit_measure = row["UNIT_MEASURE"].to_s.upcase
      value = jodi_decimal_value(row["OBS_VALUE"])

      next if country_code.blank? || period_start.blank? || value.blank?
      next unless JODI_SUPPORTED_PRODUCTS.include?(product)
      next unless JODI_DIRECT_METRICS.key?([flow_breakdown, unit_measure]) || flow_breakdown == "CLOSTLV" && unit_measure == JODI_UNIT_CONVBBL

      grouped_rows[[country_code, period_start]][[flow_breakdown, unit_measure]] << {
        product: product,
        value: value,
        assessment_code: row["ASSESSMENT_CODE"].to_s.presence,
      }
    end

    grouped_rows.flat_map do |(country_code, period_start), metric_groups|
      build_jodi_country_period_records(
        country_code: country_code,
        period_start: period_start,
        metric_groups: metric_groups,
        now: now,
        source_url: source_url,
        release_version: release_version
      )
    end
  end

  def build_jodi_country_period_records(country_code:, period_start:, metric_groups:, now:, source_url:, release_version:)
    country_reference = country_reference_for_iso2(country_code)
    return [] if country_reference[:alpha3].blank?

    metrics = {}
    metric_groups.each do |(flow_breakdown, unit_measure), entries|
      metric_config = JODI_DIRECT_METRICS[[flow_breakdown, unit_measure]]
      next if metric_config.blank?

      value = aggregate_jodi_metric_value(entries)
      next if value.blank?

      metrics[metric_config.fetch(:metric_key)] = {
        value: value,
        unit: metric_config.fetch(:unit),
        components: jodi_component_payload(entries),
      }
    end

    closing_stock = metrics.dig("closing_stock_convbbl", :value).to_d
    imports_kbd = metrics.dig("imports_kbd", :value).to_d
    if closing_stock.positive? && imports_kbd.positive?
      metrics["stocks_days"] = {
        value: (closing_stock / imports_kbd).round(6),
        unit: "days",
        derived_from: %w[closing_stock_convbbl imports_kbd],
      }
    end

    metrics.map do |metric_key, config|
      {
        country_code: country_code,
        country_code_alpha3: country_reference.fetch(:alpha3),
        country_name: country_reference.fetch(:name),
        commodity_key: "oil_crude",
        metric_key: metric_key,
        period_type: "month",
        period_start: period_start,
        period_end: period_start.end_of_month,
        value_numeric: config.fetch(:value),
        unit: config.fetch(:unit),
        source: JODI_SOURCE,
        dataset: JODI_DATASET,
        release_version: release_version,
        raw_payload: {
          "source_url" => source_url,
          "derived_from" => config[:derived_from],
          "components" => config[:components],
        }.compact,
        fetched_at: now,
        created_at: now,
        updated_at: now,
      }
    end
  end

  def aggregate_jodi_metric_value(entries)
    primary_entry = entries.find do |entry|
      entry.fetch(:product) == JODI_PRIMARY_PRODUCT
    end
    return primary_entry.fetch(:value) if primary_entry.present?

    component_entries = entries.select do |entry|
      JODI_COMPONENT_PRODUCTS.include?(entry.fetch(:product))
    end
    return if component_entries.blank?

    component_entries.sum { |entry| entry.fetch(:value).to_d }
  end

  def jodi_component_payload(entries)
    entries.each_with_object({}) do |entry, memo|
      memo[entry.fetch(:product)] = {
        value: entry.fetch(:value).to_f.round(6),
        assessment_code: entry.fetch(:assessment_code),
      }.compact
    end
  end

  def jodi_decimal_value(value)
    token = value.to_s.strip
    return if token.blank? || %w[- .. x].include?(token.downcase)

    token.to_d
  end

  def fetch_default_jodi_oil_source(now)
    errors = []

    default_jodi_oil_candidate_urls(now).each do |url|
      begin
        body = fetch_remote_body(url)
        release_version = url[%r{primaryyear(\d{4})\.csv}, 1]
        return [body, url, release_version]
      rescue StandardError => e
        errors << "#{url}: #{e.message}"
      end
    end

    raise "Unable to fetch default JODI oil source. #{errors.join(' | ')}"
  end

  def default_jodi_oil_candidate_urls(now)
    year = now.year
    (year - DEFAULT_JODI_OIL_LOOKBACK_YEARS..year).to_a.reverse.map do |candidate_year|
      format(DEFAULT_JODI_OIL_SOURCE_URL_TEMPLATE, year: candidate_year)
    end
  end

  def country_reference_for_iso2(country_code)
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
end
