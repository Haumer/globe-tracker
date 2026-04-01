require "json"
require "net/http"

class TradeFlowRefreshService
  extend Refreshable
  include TabularDatasetLoader

  DEFAULT_SOURCE_PATH = Rails.root.join("tmp", "imports", "strategic_trade_flows.csv.gz").freeze
  SOURCE_PATH_ENV = "STRATEGIC_TRADE_FLOWS_SOURCE_PATH".freeze
  SOURCE_URL_ENV = "STRATEGIC_TRADE_FLOWS_SOURCE_URL".freeze
  COMTRADE_PRIMARY_SECRET_ENV = "COMTRADE_PRIMARY_SECRET".freeze
  COMTRADE_SECONDARY_SECRET_ENV = "COMTRADE_SECONDARY_SECRET".freeze
  COMTRADE_API_BASE = "https://comtradeapi.un.org".freeze
  COMTRADE_LIVE_UPDATE_PATH = "/data/v1/getLiveUpdate".freeze
  COMTRADE_AVAILABILITY_PATH = "/data/v1/getDa/C/M/HS".freeze
  COMTRADE_FINAL_DATA_PATH = "/data/v1/get/C/M/HS".freeze
  COMTRADE_DATASET = "comtrade_hs_monthly".freeze
  COMTRADE_MAX_RECORDS = 250_000
  COMTRADE_BOOTSTRAP_PERIODS = 1
  COMTRADE_MAX_LOOKBACK_MONTHS = 24
  COMTRADE_REPORTERS_PER_REQUEST = 50
  COMTRADE_MAX_REQUEST_GROUPS_PER_REFRESH = 1
  COMTRADE_DEFAULT_RETRY_AFTER = 1.hour
  CSV_SOURCE_STATUS = {
    provider: "strategic_trade_flows",
    display_name: "Strategic Trade Flows",
    feed_kind: "trade_flows",
  }.freeze
  COMTRADE_SOURCE_STATUS = {
    provider: "un_comtrade",
    display_name: "UN Comtrade",
    feed_kind: "trade_flows",
    endpoint_url: "#{COMTRADE_API_BASE}#{COMTRADE_LIVE_UPDATE_PATH}",
  }.freeze

  refreshes model: TradeFlowSnapshot, interval: 1.hour, column: :fetched_at

  class ComtradeHttpError < StandardError
    attr_reader :http_status, :response_body, :retry_after

    def initialize(message, http_status:, response_body: nil, retry_after: nil)
      super(message)
      @http_status = http_status
      @response_body = response_body
      @retry_after = retry_after
    end
  end

  def refresh
    now = Time.current
    return refresh_from_comtrade(now) if comtrade_configured?

    path = configured_source_path
    url = configured_source_url
    return record_disabled(now) if path.blank? && url.blank?

    refresh_from_csv(now, path: path, url: url)
  rescue StandardError => e
    record_error(e)
    0
  end

  private

  def refresh_from_csv(now, path:, url:)
    rows = csv_rows_from_source(path: path, url: url)
    records = rows.filter_map { |row| build_record(row, now) }
    upsert_records(records)

    SourceFeedStatusRecorder.record(
      **CSV_SOURCE_STATUS,
      endpoint_url: url.presence || path,
      status: "success",
      records_fetched: rows.size,
      records_stored: records.size,
      metadata: {
        source_mode: "csv",
        source_path: path,
        source_url: url,
        strategic_commodity_keys: SupplyChainCatalog::STRATEGIC_COMMODITIES.keys,
      },
      occurred_at: now
    )

    records.size
  end

  def refresh_from_comtrade(now)
    return 0 if comtrade_backoff_active?(now)

    bootstrapping = bootstrap_required?
    request_groups = pending_request_groups.presence || request_groups_for_candidates(comtrade_candidates(bootstrapping: bootstrapping))
    @current_comtrade_request_groups = request_groups
    active_groups = request_groups.first(COMTRADE_MAX_REQUEST_GROUPS_PER_REFRESH)
    remaining_groups = request_groups.drop(active_groups.size)
    fetched_rows = 0
    stored_rows = 0

    active_groups.each do |request_group|
      raw_rows = fetch_comtrade_records(request_group)
      fetched_rows += raw_rows.size

      records = raw_rows.filter_map do |row|
        build_record_from_comtrade(row, release_versions: request_group[:release_versions], now: now)
      end

      replace_comtrade_slices!(request_group: request_group, records: records)
      stored_rows += records.size
    end

    SourceFeedStatusRecorder.record(
      **COMTRADE_SOURCE_STATUS,
      status: "success",
      records_fetched: fetched_rows,
      records_stored: stored_rows,
      metadata: {
        source_mode: "api",
        bootstrap_mode: bootstrapping,
        request_groups_processed: active_groups.size,
        request_groups_remaining: remaining_groups.size,
        pending_request_groups: remaining_groups,
        strategic_cmd_codes: strategic_cmd_codes,
      },
      occurred_at: now
    )

    stored_rows
  end

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

  def build_record_from_comtrade(row, release_versions:, now:)
    reporter_alpha3 = row["reporterISO"].to_s.upcase
    partner_alpha3 = row["partnerISO"].to_s.upcase
    hs_code = row["cmdCode"].to_s.strip
    commodity_key = SupplyChainCatalog.commodity_key_for_hs(hs_code)
    return if reporter_alpha3.blank? || partner_alpha3.blank?
    return if partner_alpha3 == "W00"
    return if commodity_key.blank?

    period_start = parse_period_start(row["period"])
    return if period_start.blank?

    {
      reporter_country_code: nil,
      reporter_country_code_alpha3: reporter_alpha3,
      reporter_country_name: row["reporterDesc"].to_s.strip.presence,
      partner_country_code: nil,
      partner_country_code_alpha3: partner_alpha3,
      partner_country_name: row["partnerDesc"].to_s.strip.presence,
      flow_direction: normalized_flow_direction_from_comtrade(row),
      commodity_key: commodity_key,
      commodity_name: SupplyChainCatalog.commodity_name_for(commodity_key),
      hs_code: hs_code,
      period_type: "month",
      period_start: period_start,
      period_end: period_start.end_of_month,
      trade_value_usd: decimal_value(row["primaryValue"] || row["cifvalue"] || row["fobvalue"]),
      quantity: decimal_value(row["qty"] || row["netWgt"]),
      quantity_unit: row["qtyUnitAbbr"].to_s.strip.presence || (row["netWgt"].present? ? "kg" : nil),
      source: "un_comtrade",
      dataset: COMTRADE_DATASET,
      release_version: release_versions[row["reporterCode"].to_s],
      raw_payload: row,
      fetched_at: now,
      created_at: now,
      updated_at: now,
    }
  end

  def comtrade_candidates(bootstrapping:)
    live_candidates = live_update_candidates
    bootstrap_candidates = bootstrapping ? availability_bootstrap_candidates(live_candidates) : []

    dedupe_candidates(live_candidates + bootstrap_candidates)
      .sort_by { |candidate| [candidate[:period_token].to_s, candidate[:reporter_code].to_s] }
      .reverse
  end

  def live_update_candidates
    payload = comtrade_json(path: COMTRADE_LIVE_UPDATE_PATH, params: {})

    Array(payload["data"]).filter_map do |row|
      next unless row["typeCode"].to_s == "C"
      next unless row["freqCode"].to_s == "M"
      next unless supported_hs_classification?(row["classificationCode"], row["classificationSearchCode"])

      period_token = normalize_period_token(row["period"])
      reporter_code = row["reporterCode"].to_s
      next if period_token.blank? || reporter_code.blank?
      next unless recent_period_token?(period_token)

      {
        reporter_code: reporter_code,
        reporter_iso3: row["reporterISO"].to_s.upcase.presence,
        period_token: period_token,
        release_version: row["lastUpdated"] || row["completedAt"] || row["queuedAt"] || row["startedAt"],
      }
    end
  end

  def availability_bootstrap_candidates(live_candidates)
    bootstrap_period_tokens(live_candidates).flat_map do |period_token|
      availability_candidates_for(period_token)
    end
  end

  def availability_candidates_for(period_token)
    payload = comtrade_json(
      path: COMTRADE_AVAILABILITY_PATH,
      params: {
        period: period_token,
      }
    )

    Array(payload["data"]).filter_map do |row|
      next if row["reporterCode"].blank?
      next if row["totalRecords"].to_i <= 0
      next unless supported_hs_classification?(row["classificationCode"], row["classificationSearchCode"])
      next unless recent_period_token?(period_token)

      {
        reporter_code: row["reporterCode"].to_s,
        reporter_iso3: row["reporterISO"].to_s.upcase.presence,
        period_token: period_token,
        release_version: row["lastReleased"] || row["firstReleased"],
      }
    end
  end

  def bootstrap_period_tokens(live_candidates)
    live_periods = Array(live_candidates)
      .filter_map { |candidate| normalize_period_token(candidate[:period_token]) }
      .uniq
      .sort
      .reverse
      .first(COMTRADE_BOOTSTRAP_PERIODS)

    return live_periods if live_periods.present?

    [Date.current.prev_month.strftime("%Y%m")]
  end

  def fetch_comtrade_records(candidate)
    fetch_comtrade_records_for_codes(candidate, strategic_cmd_codes)
  end

  def fetch_comtrade_records_for_codes(request_group, cmd_codes)
    payload = comtrade_json(
      path: COMTRADE_FINAL_DATA_PATH,
      params: {
        reportercode: request_group.fetch(:reporter_codes).join(","),
        flowCode: "M",
        period: request_group.fetch(:period_token),
        cmdCode: cmd_codes.join(","),
        maxRecords: COMTRADE_MAX_RECORDS,
        format: "JSON",
        includeDesc: true,
        breakdownMode: "classic",
      }
    )

    rows = Array(payload["data"])
    return rows unless truncated_payload?(payload, rows)

    if cmd_codes.size == 1
      raise ComtradeHttpError.new(
        "Comtrade response truncated for reporters #{request_group[:reporter_codes].join(',')} period #{request_group[:period_token]} cmdCode #{cmd_codes.first}",
        http_status: 200,
        response_body: payload.to_json
      )
    end

    midpoint = cmd_codes.size / 2
    fetch_comtrade_records_for_codes(request_group, cmd_codes.first(midpoint)) +
      fetch_comtrade_records_for_codes(request_group, cmd_codes.drop(midpoint))
  end

  def replace_comtrade_slices!(request_group:, records:)
    period_start = parse_period_start(request_group[:period_token])
    reporter_alpha3s = records.map { |record| record[:reporter_country_code_alpha3] }.compact.uniq
    reporter_alpha3s = request_group[:reporter_iso3_by_code].values.compact.uniq if reporter_alpha3s.blank?

    if reporter_alpha3s.present? && period_start.present?
      TradeFlowSnapshot.where(
        reporter_country_code_alpha3: reporter_alpha3s,
        period_start: period_start,
        dataset: COMTRADE_DATASET,
        source: "un_comtrade"
      ).delete_all
    end

    upsert_records(records)
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

  def comtrade_configured?
    comtrade_subscription_keys.any?
  end

  def comtrade_subscription_keys
    @comtrade_subscription_keys ||= [
      ENV[COMTRADE_PRIMARY_SECRET_ENV].presence,
      ENV[COMTRADE_SECONDARY_SECRET_ENV].presence,
    ].compact.uniq
  end

  def bootstrap_required?
    pending_request_groups.any? || TradeFlowSnapshot.where(source: "un_comtrade", dataset: COMTRADE_DATASET).none?
  end

  def strategic_cmd_codes
    @strategic_cmd_codes ||= SupplyChainCatalog::STRATEGIC_COMMODITIES.values
      .flat_map { |config| Array(config[:hs_prefixes]) }
      .map(&:to_s)
      .uniq
      .sort
  end

  def dedupe_candidates(candidates)
    candidates.each_with_object({}) do |candidate, memo|
      key = [candidate[:reporter_code].to_s, candidate[:period_token].to_s]
      memo[key] ||= candidate
    end.values
  end

  def request_groups_for_candidates(candidates)
    candidates
      .group_by { |candidate| candidate[:period_token].to_s }
      .flat_map do |period_token, period_candidates|
        period_candidates
          .sort_by { |candidate| candidate[:reporter_code].to_i }
          .each_slice(COMTRADE_REPORTERS_PER_REQUEST)
          .map do |slice|
            {
              period_token: period_token,
              reporter_codes: slice.map { |candidate| candidate[:reporter_code].to_s },
              reporter_iso3_by_code: slice.to_h { |candidate| [candidate[:reporter_code].to_s, candidate[:reporter_iso3]] },
              release_versions: slice.to_h { |candidate| [candidate[:reporter_code].to_s, candidate[:release_version]] },
            }
          end
      end
      .sort_by { |group| [group[:period_token].to_s, group[:reporter_codes].first.to_i] }
      .reverse
  end

  def pending_request_groups
    metadata = comtrade_status_record&.metadata
    groups = metadata.is_a?(Hash) ? metadata["pending_request_groups"] : nil
    Array(groups).map do |group|
      next unless group.is_a?(Hash)
      next unless recent_period_token?(group["period_token"])

      {
        period_token: group["period_token"].to_s,
        reporter_codes: Array(group["reporter_codes"]).map(&:to_s),
        reporter_iso3_by_code: (group["reporter_iso3_by_code"] || {}).to_h.transform_keys(&:to_s),
        release_versions: (group["release_versions"] || {}).to_h.transform_keys(&:to_s),
      }
    end.compact
  end

  def truncated_payload?(payload, rows)
    total_count = payload["count"].to_i
    total_count > rows.size || rows.size >= COMTRADE_MAX_RECORDS
  end

  def supported_hs_classification?(classification_code, classification_search_code = nil)
    code = classification_code.to_s.upcase
    search_code = classification_search_code.to_s.upcase

    code == "HS" || search_code == "HS" || code.match?(/\AH[4-6]\z/)
  end

  def comtrade_json(path:, params:)
    last_error = nil

    comtrade_subscription_keys.each do |subscription_key|
      uri = build_comtrade_uri(path, params.merge("subscription-key" => subscription_key))
      response = http_get_response(uri)

      begin
        case response
        when Net::HTTPSuccess
          return JSON.parse(response.body.presence || "{}")
        when Net::HTTPUnauthorized, Net::HTTPForbidden, Net::HTTPTooManyRequests
          last_error = ComtradeHttpError.new(
            "Comtrade request failed with HTTP #{response.code}",
            http_status: response.code.to_i,
            response_body: response.body,
            retry_after: response["retry-after"]
          )
          next
        else
          raise ComtradeHttpError.new(
            "Comtrade request failed with HTTP #{response.code}",
            http_status: response.code.to_i,
            response_body: response.body,
            retry_after: response["retry-after"]
          )
        end
      rescue JSON::ParserError => e
        raise ComtradeHttpError.new(
          "Comtrade returned invalid JSON: #{e.message}",
          http_status: response.code.to_i,
          response_body: response.body
        )
      end
    end

    raise(last_error || ComtradeHttpError.new("Comtrade credentials are not configured", http_status: nil))
  end

  def build_comtrade_uri(path, params)
    uri = URI("#{COMTRADE_API_BASE}#{path}")
    uri.query = URI.encode_www_form(params.compact.transform_keys(&:to_s))
    uri
  end

  def http_get_response(uri)
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 15, read_timeout: 120) do |http|
      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/json"
      http.request(request)
    end
  end

  def record_disabled(now)
    SourceFeedStatusRecorder.record(
      **CSV_SOURCE_STATUS,
      endpoint_url: nil,
      status: "disabled",
      metadata: {
        source_mode: "csv",
        expected_path_env: SOURCE_PATH_ENV,
        expected_url_env: SOURCE_URL_ENV,
        comtrade_primary_secret_env: COMTRADE_PRIMARY_SECRET_ENV,
        comtrade_secondary_secret_env: COMTRADE_SECONDARY_SECRET_ENV,
      },
      occurred_at: now
    )
    0
  end

  def record_error(error)
    if comtrade_configured?
      if error.respond_to?(:http_status) && error.http_status.to_i == 429
        retry_at = retry_at_for(error)
        SourceFeedStatusRecorder.record(
          **COMTRADE_SOURCE_STATUS,
          status: "rate_limited",
          http_status: error.http_status,
          error_message: error.message,
          metadata: {
            source_mode: "api",
            retry_after_at: retry_at&.iso8601,
            pending_request_groups: @current_comtrade_request_groups || pending_request_groups,
            strategic_cmd_codes: strategic_cmd_codes,
          },
          occurred_at: Time.current
        )
      else
        SourceFeedStatusRecorder.record(
          **COMTRADE_SOURCE_STATUS,
          status: "error",
          http_status: error.respond_to?(:http_status) ? error.http_status : nil,
          error_message: error.message,
          metadata: {
            source_mode: "api",
            strategic_cmd_codes: strategic_cmd_codes,
          },
          occurred_at: Time.current
        )
      end
    else
      SourceFeedStatusRecorder.record(
        **CSV_SOURCE_STATUS,
        endpoint_url: configured_source_url.presence || configured_source_path,
        status: "error",
        error_message: error.message,
        metadata: {
          source_mode: "csv",
        },
        occurred_at: Time.current
      )
    end

    Rails.logger.error("TradeFlowRefreshService: #{error.message}")
  end

  def comtrade_status_record
    @comtrade_status_record ||= SourceFeedStatus.find_by(feed_key: "un_comtrade:https://comtradeapi.un.org/data/v1/getLiveUpdate")
  end

  def comtrade_backoff_active?(now)
    retry_after = comtrade_status_record&.metadata&.dig("retry_after_at")
    retry_at = Time.zone.parse(retry_after.to_s)
    retry_at.present? && retry_at > now
  rescue ArgumentError
    false
  end

  def retry_at_for(error)
    header = error.respond_to?(:retry_after) ? error.retry_after : nil
    seconds = Integer(header, exception: false)
    return Time.current + seconds.seconds if seconds.present?

    Time.current + COMTRADE_DEFAULT_RETRY_AFTER
  end

  def normalized_flow_direction(row)
    direction = value_for(row, "flow_direction", "direction").to_s.downcase
    return "import" if direction.blank?
    return "export" if direction.include?("export")
    return "import" if direction.include?("import")

    direction
  end

  def normalized_flow_direction_from_comtrade(row)
    flow_code = row["flowCode"].to_s.upcase
    return "import" if flow_code == "M"
    return "export" if flow_code == "X"

    normalized_flow_direction({ "flow_direction" => row["flowDesc"] })
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

  def normalize_period_token(value)
    token = value.to_s.strip
    return if token.blank?

    digits = token.gsub(/\D/, "")
    return digits if digits.match?(/\A\d{6}\z/)

    if digits.match?(/\A\d{4}\z/)
      return "#{digits}01"
    end

    Date.parse(token).strftime("%Y%m")
  rescue Date::Error
    nil
  end

  def recent_period_token?(period_token)
    period_start = parse_period_start(period_token)
    return false if period_start.blank?

    period_start >= COMTRADE_MAX_LOOKBACK_MONTHS.months.ago.to_date.beginning_of_month
  end

  def parse_period_start(value)
    token = value.to_s.strip
    return if token.blank?

    if token.match?(/\A\d{6}\z/)
      Date.strptime("#{token}01", "%Y%m%d")
    elsif token.match?(/\A\d{4}-\d{2}\z/)
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
    return "month" if value.match?(/\A\d{6}\z/)
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

  def decimal_value(value)
    value.present? ? value.to_d : nil
  end

  def normalize_iso2(value)
    code = value.to_s.upcase
    code.match?(/\A[A-Z]{2}\z/) ? code : nil
  end
end
