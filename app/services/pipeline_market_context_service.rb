class PipelineMarketContextService
  TYPE_COMMODITY_KEYS = {
    "oil" => %w[oil_crude],
    "gas" => %w[gas_nat lng],
    "products" => %w[oil_refined],
  }.freeze

  TYPE_BENCHMARK_SYMBOLS = {
    "oil" => %w[OIL_BRENT OIL_WTI],
    "gas" => %w[GAS_NAT LNG],
    "products" => %w[OIL_BRENT OIL_WTI],
  }.freeze

  MAX_SERIES_POINTS = 48
  SERIES_LOOKBACK = 14.days

  def self.call(pipeline, detail: false)
    new(pipeline, detail: detail).call
  end

  def initialize(pipeline, detail: false)
    @pipeline = pipeline
    @detail = detail
  end

  def call
    commodity_keys = TYPE_COMMODITY_KEYS.fetch(@pipeline.pipeline_type.to_s.downcase, [])
    benchmark_symbols = TYPE_BENCHMARK_SYMBOLS.fetch(@pipeline.pipeline_type.to_s.downcase, [])
    benchmarks = serialize_quotes(latest_quotes(benchmark_symbols))
    downstream = serialize_dependencies(top_dependencies(commodity_keys))
    route_pressure = serialize_exposures(top_exposures(commodity_keys))

    payload = {
      summary: build_summary(benchmarks, downstream, route_pressure),
      risk_level: derive_risk_level(benchmarks, downstream, route_pressure),
      highlights: build_highlights(benchmarks, downstream, route_pressure),
      benchmarks: benchmarks,
      downstream_countries: downstream,
      route_pressure: route_pressure,
    }

    if @detail
      payload[:benchmark_series] = benchmark_series(benchmark_symbols)
      payload[:coverage] = {
        downstream_observed: downstream.count { |row| row[:estimated] == false },
        downstream_estimated: downstream.count { |row| row[:estimated] == true },
        route_observed: route_pressure.count { |row| row[:estimated] == false },
        route_estimated: route_pressure.count { |row| row[:estimated] == true },
      }
    end

    payload
  end

  private

  def latest_quotes(symbols)
    return [] if symbols.blank?

    CommodityPrice
      .where(symbol: symbols)
      .select("DISTINCT ON (symbol) *")
      .order(:symbol, recorded_at: :desc)
      .to_a
  end

  def benchmark_series(symbols)
    return {} if symbols.blank?

    rows = CommodityPrice
      .where(symbol: symbols)
      .where("recorded_at >= ?", SERIES_LOOKBACK.ago)
      .order(:symbol, :recorded_at)
      .pluck(:symbol, :recorded_at, :price)

    rows.group_by(&:first).transform_values do |entries|
      sampled_entries(entries).map do |(_symbol, recorded_at, price)|
        {
          recorded_at: recorded_at&.iso8601,
          price: price&.to_f,
        }
      end
    end
  end

  def top_dependencies(commodity_keys)
    return [] if commodity_keys.blank?

    CountryCommodityDependency
      .where(commodity_key: commodity_keys)
      .order(dependency_score: :desc, import_share_gdp_pct: :desc, import_value_usd: :desc)
      .limit(5)
      .to_a
  end

  def top_exposures(commodity_keys)
    return [] if commodity_keys.blank?

    rows = CountryChokepointExposure
      .where(commodity_key: commodity_keys)
      .order(exposure_score: :desc, dependency_score: :desc, supplier_share_pct: :desc)
      .limit(24)
      .to_a

    uniq = []
    rows.each do |row|
      next if uniq.any? { |entry| entry.chokepoint_name == row.chokepoint_name }

      uniq << row
      break if uniq.size >= 3
    end
    uniq
  end

  def serialize_quotes(quotes)
    quotes.map do |quote|
      {
        symbol: quote.symbol,
        name: quote.name,
        category: quote.category,
        price: quote.price&.to_f,
        change_pct: quote.change_pct&.to_f,
        unit: quote.unit,
        recorded_at: quote.recorded_at&.iso8601,
      }
    end
  end

  def serialize_dependencies(rows)
    rows.map do |row|
      {
        country_name: row.country_name,
        country_code_alpha3: row.country_code_alpha3,
        commodity_name: row.commodity_name,
        dependency_score: row.dependency_score&.to_f,
        import_share_gdp_pct: row.import_share_gdp_pct&.to_f,
        supplier_count: row.supplier_count,
        estimated: estimated_row?(row),
      }
    end
  end

  def serialize_exposures(rows)
    chokepoint_status_by_name = @detail ? current_chokepoint_status_by_name : {}

    rows.map do |row|
      {
        chokepoint_name: row.chokepoint_name,
        commodity_name: row.commodity_name,
        exposure_score: row.exposure_score&.to_f,
        dependency_score: row.dependency_score&.to_f,
        supplier_share_pct: row.supplier_share_pct&.to_f,
        status: chokepoint_status_by_name[row.chokepoint_name],
        estimated: estimated_row?(row),
      }
    end
  end

  def estimated_row?(row)
    metadata = row.metadata || {}
    metadata["estimated"] == true || metadata[:estimated] == true
  end

  def sampled_entries(entries)
    return [] if entries.blank?
    return entries if entries.length <= MAX_SERIES_POINTS

    step = (entries.length.to_f / MAX_SERIES_POINTS).ceil
    sampled = entries.each_with_index.filter_map { |entry, idx| (idx % step).zero? ? entry : nil }
    sampled << entries.last unless sampled.last == entries.last
    sampled
  end

  def current_chokepoint_status_by_name
    snapshot = ChokepointSnapshotService.fetch_or_enqueue
    payload = snapshot&.payload.presence || ChokepointSnapshotService.empty_payload
    chokepoints = payload["chokepoints"] || payload[:chokepoints] || []

    chokepoints.each_with_object({}) do |entry, memo|
      name = entry["name"] || entry[:name]
      status = entry["status"] || entry[:status]
      memo[name] = status if name.present? && status.present?
    end
  rescue StandardError
    {}
  end

  def build_summary(benchmarks, downstream, route_pressure)
    strongest_benchmark = benchmarks.max_by { |quote| quote[:change_pct].to_f.abs }
    top_dependency = downstream.max_by { |row| row[:dependency_score].to_f }
    top_route = route_pressure.max_by { |row| row[:exposure_score].to_f }

    summary_parts = []
    summary_parts << benchmark_summary(strongest_benchmark) if strongest_benchmark
    summary_parts << dependency_summary(top_dependency) if top_dependency
    summary_parts << route_pressure_summary(top_route) if top_route

    return "Linked market context unavailable." if summary_parts.empty?

    summary_parts.join(" · ")
  end

  def build_highlights(benchmarks, downstream, route_pressure)
    [
      benchmark_summary(benchmarks.max_by { |quote| quote[:change_pct].to_f.abs }),
      dependency_summary(downstream.max_by { |row| row[:dependency_score].to_f }),
      route_pressure_summary(route_pressure.max_by { |row| row[:exposure_score].to_f }),
    ].compact
  end

  def derive_risk_level(benchmarks, downstream, route_pressure)
    max_benchmark_move = benchmarks.map { |quote| quote[:change_pct].to_f.abs }.max.to_f
    max_dependency = downstream.map { |row| row[:dependency_score].to_f }.max.to_f
    max_route_pressure = route_pressure.map { |row| row[:exposure_score].to_f }.max.to_f

    score = [max_benchmark_move / 4.0, max_dependency, max_route_pressure].max
    return "critical" if score >= 0.8
    return "high" if score >= 0.6
    return "medium" if score >= 0.35

    "low"
  end

  def benchmark_summary(quote)
    return nil unless quote

    delta = quote[:change_pct]
    delta_text = delta.nil? ? "flat" : format("%+.2f%%", delta)
    "#{quote[:name] || quote[:symbol]} #{delta_text}"
  end

  def dependency_summary(row)
    return nil unless row

    "Highest downstream dependency: #{row[:country_name]} #{format('%.2f', row[:dependency_score].to_f)}#{row[:estimated] ? ' est.' : ''}"
  end

  def route_pressure_summary(row)
    return nil unless row

    status = row[:status].present? ? " (#{row[:status]})" : ""
    "Primary route pressure: #{row[:chokepoint_name]} #{format('%.2f', row[:exposure_score].to_f)}#{status}#{row[:estimated] ? ' est.' : ''}"
  end
end
