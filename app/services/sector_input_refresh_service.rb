class SectorInputRefreshService
  extend Refreshable
  include TabularDatasetLoader

  DEFAULT_SOURCE_PATH = Rails.root.join("tmp", "imports", "sector_inputs.csv.gz").freeze
  SOURCE_PATH_ENV = "SECTOR_INPUTS_SOURCE_PATH".freeze
  SOURCE_URL_ENV = "SECTOR_INPUTS_SOURCE_URL".freeze
  SOURCE_STATUS = {
    provider: "sector_inputs",
    display_name: "Sector Input Coefficients",
    feed_kind: "sector_inputs",
  }.freeze

  refreshes model: SectorInputSnapshot, interval: 24.hours, column: :fetched_at

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
    Rails.logger.error("SectorInputRefreshService: #{e.message}")
    0
  end

  private

  def build_record(row, now)
    sector_key = value_for(row, "sector_key")
    input_key = value_for(row, "input_key")
    input_kind = value_for(row, "input_kind")
    period_year = integer_for(row, "period_year", "year")
    return if sector_key.blank? || input_key.blank? || input_kind.blank? || period_year.blank?

    country_alpha3 = value_for(row, "country_iso3", "country_code_alpha3")
    scope_key = country_alpha3.present? ? country_alpha3.upcase : "global"

    {
      scope_key: scope_key,
      country_code: normalize_iso2(value_for(row, "country_iso2", "country_code")),
      country_code_alpha3: country_alpha3&.upcase,
      country_name: value_for(row, "country_name"),
      sector_key: sector_key,
      sector_name: value_for(row, "sector_name") || sector_key.humanize,
      input_kind: input_kind,
      input_key: input_key,
      input_name: value_for(row, "input_name"),
      coefficient: decimal_for(row, "coefficient", "value_numeric", "value"),
      period_year: period_year,
      source: value_for(row, "source") || "sector_inputs",
      dataset: value_for(row, "dataset") || "normalized_sector_inputs",
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
      SectorInputSnapshot.upsert_all(batch, unique_by: :idx_sector_input_snapshots_unique_period)
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
