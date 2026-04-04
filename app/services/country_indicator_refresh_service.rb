require "digest"

class CountryIndicatorRefreshService
  extend HttpClient
  extend Refreshable

  WORLD_BANK_API = "https://api.worldbank.org/v2".freeze
  RECENT_PERIOD_LIMIT = 8

  refreshes model: CountryIndicatorSnapshot, interval: 24.hours, column: :fetched_at

  def refresh
    now = Time.current
    indicator_records = []
    sector_records = []
    fetched_rows = 0

    SupplyChainCatalog::WORLD_BANK_SERIES.each do |series_key, config|
      payload = fetch_series(series_key)
      rows = payload.is_a?(Array) ? payload.last : []
      meta = payload.is_a?(Array) ? payload.first : {}
      fetched_rows += rows.to_a.size

      rows.to_a.each do |row|
        next if row["value"].blank?
        next unless valid_country_row?(row)

        built = build_record(row, config, series_key, meta, now)
        next if built.blank?

        case config[:target]
        when :indicator then indicator_records << built
        when :sector then sector_records << built
        end
      end
    end

    upsert_country_indicators(indicator_records)
    upsert_country_sectors(sector_records)

    SourceFeedStatusRecorder.record(
      **SupplyChainCatalog::WORLD_BANK_SOURCE,
      status: "success",
      records_fetched: fetched_rows,
      records_stored: indicator_records.size + sector_records.size,
      metadata: {
        indicator_series: SupplyChainCatalog::WORLD_BANK_SERIES.keys,
        recent_period_limit: RECENT_PERIOD_LIMIT,
      },
      occurred_at: now
    )

    indicator_records.size + sector_records.size
  rescue StandardError => e
    SourceFeedStatusRecorder.record(
      **SupplyChainCatalog::WORLD_BANK_SOURCE,
      status: "error",
      error_message: e.message,
      metadata: {
        indicator_series: SupplyChainCatalog::WORLD_BANK_SERIES.keys,
      },
      occurred_at: Time.current
    )
    Rails.logger.error("CountryIndicatorRefreshService: #{e.message}")
    0
  end

  private

  def fetch_series(series_key)
    uri = URI("#{WORLD_BANK_API}/country/all/indicator/#{series_key}?format=json&per_page=20000&mrv=#{RECENT_PERIOD_LIMIT}")
    self.class.http_get(
      uri,
      open_timeout: 10,
      read_timeout: 60,
      cache_key: "http:world_bank:#{Digest::MD5.hexdigest(uri.to_s)}",
      cache_ttl: 24.hours
    )
  end

  def build_record(row, config, series_key, meta, now)
    period_start = parse_year_start(row["date"])
    return if period_start.blank?

    shared = {
      country_code: normalize_iso2(row.dig("country", "id")),
      country_code_alpha3: row["countryiso3code"].to_s.upcase,
      country_name: row.dig("country", "value").to_s.strip,
      source: "world_bank",
      dataset: "wdi",
      release_version: meta.is_a?(Hash) ? meta["lastupdated"] : nil,
      raw_payload: row,
      fetched_at: now,
      created_at: now,
      updated_at: now,
    }

    case config[:target]
    when :indicator
      shared.merge(
        indicator_key: config.fetch(:indicator_key),
        indicator_name: config.fetch(:indicator_name),
        period_type: "year",
        period_start: period_start,
        period_end: period_start.end_of_year,
        value_numeric: row["value"],
        unit: config[:unit],
        series_key: series_key
      )
    when :sector
      shared.merge(
        sector_key: config.fetch(:sector_key),
        sector_name: config.fetch(:sector_name),
        metric_key: config.fetch(:metric_key),
        metric_name: config.fetch(:metric_name),
        period_year: period_start.year,
        value_numeric: row["value"],
        unit: config[:unit]
      )
    end
  end

  def upsert_country_indicators(records)
    return if records.blank?

    records.each_slice(1000) do |batch|
      CountryIndicatorSnapshot.upsert_all(batch, unique_by: :idx_country_indicator_snapshots_unique_period)
    end
  end

  def upsert_country_sectors(records)
    return if records.blank?

    records.each_slice(1000) do |batch|
      CountrySectorSnapshot.upsert_all(batch, unique_by: :idx_country_sector_snapshots_unique_period)
    end
  end

  def parse_year_start(value)
    year = value.to_i
    return if year <= 0

    Date.new(year, 1, 1)
  rescue Date::Error
    nil
  end

  def valid_country_row?(row)
    row["countryiso3code"].to_s.match?(/\A[A-Z]{3}\z/) &&
      normalize_iso2(row.dig("country", "id")).present?
  end

  def normalize_iso2(value)
    code = value.to_s.upcase
    code.match?(/\A[A-Z]{2}\z/) ? code : nil
  end
end
