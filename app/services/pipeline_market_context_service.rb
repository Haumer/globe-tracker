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

  def self.call(pipeline)
    new(pipeline).call
  end

  def initialize(pipeline)
    @pipeline = pipeline
  end

  def call
    commodity_keys = TYPE_COMMODITY_KEYS.fetch(@pipeline.pipeline_type.to_s.downcase, [])
    benchmark_symbols = TYPE_BENCHMARK_SYMBOLS.fetch(@pipeline.pipeline_type.to_s.downcase, [])

    {
      benchmarks: serialize_quotes(latest_quotes(benchmark_symbols)),
      downstream_countries: serialize_dependencies(top_dependencies(commodity_keys)),
      route_pressure: serialize_exposures(top_exposures(commodity_keys)),
    }
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
    rows.map do |row|
      {
        chokepoint_name: row.chokepoint_name,
        commodity_name: row.commodity_name,
        exposure_score: row.exposure_score&.to_f,
        dependency_score: row.dependency_score&.to_f,
        supplier_share_pct: row.supplier_share_pct&.to_f,
        estimated: estimated_row?(row),
      }
    end
  end

  def estimated_row?(row)
    metadata = row.metadata || {}
    metadata["estimated"] == true || metadata[:estimated] == true
  end
end
