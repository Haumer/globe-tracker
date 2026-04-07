class SupplyChainLensService
  DISPLAY_ROW_LIMIT = 8
  RUNWAY_CARD_LIMIT = 6
  MAX_RUNWAY_DAYS = 400

  DEPENDENCY_BUCKETS = [
    { key: "critical", label: "Critical", min: 0.65, color: "#ff7043" },
    { key: "high", label: "High", min: 0.45, color: "#ffb74d" },
    { key: "moderate", label: "Moderate", min: 0.25, color: "#ffd54f" },
    { key: "watch", label: "Watch", min: 0.0, color: "#80cbc4" },
  ].freeze

  PRIMARY_COMMODITY_BY_CHOKEPOINT = {
    "hormuz" => "oil_crude",
    "suez" => "oil_crude",
    "bab_el_mandeb" => "oil_crude",
    "malacca" => "oil_crude",
    "bosphorus" => "wheat",
    "panama" => "lng",
    "taiwan_strait" => "semiconductors",
    "danish_straits" => "oil_crude",
    "cape" => "oil_crude",
    "cape_horn" => "oil_crude",
    "mozambique" => "lng",
  }.freeze

  PIPELINE_COMMODITY_BY_TYPE = {
    "oil" => "oil_crude",
    "gas" => "gas_nat",
    "products" => "oil_refined",
  }.freeze

  class << self
    def call(chokepoint_key:, commodity_key:)
      new(chokepoint_key: chokepoint_key, commodity_key: commodity_key).call
    end

    def primary_commodity_for_chokepoint(chokepoint_key)
      PRIMARY_COMMODITY_BY_CHOKEPOINT[chokepoint_key.to_s]
    end

    def primary_commodity_for_pipeline_type(pipeline_type)
      PIPELINE_COMMODITY_BY_TYPE[pipeline_type.to_s.downcase]
    end
  end

  def initialize(chokepoint_key:, commodity_key:)
    @chokepoint_key = chokepoint_key.to_s
    @commodity_key = commodity_key.to_s
  end

  def call
    return empty_payload if @chokepoint_key.blank? || @commodity_key.blank?

    exposures = exposure_rows
    dependency_rows = build_dependency_rows(exposures)
    metrics_by_country = latest_energy_metrics_by_country(dependency_rows.map { |row| row[:country_code_alpha3] })
    dependency_map = build_dependency_map(dependency_rows)
    reserve_runway = build_reserve_runway(dependency_rows, metrics_by_country)
    downstream_pathway = build_downstream_pathway(dependency_map, reserve_runway)

    {
      chokepoint_key: @chokepoint_key,
      chokepoint_name: chokepoint_name,
      commodity_key: @commodity_key,
      commodity_name: commodity_name,
      dependency_map: dependency_map,
      reserve_runway: reserve_runway,
      downstream_pathway: downstream_pathway,
    }
  end

  private

  def empty_payload
    {
      chokepoint_key: @chokepoint_key,
      chokepoint_name: chokepoint_name,
      commodity_key: @commodity_key,
      commodity_name: commodity_name,
      dependency_map: {
        summary: "No dependency rows available for this route.",
        rows: [],
        buckets: DEPENDENCY_BUCKETS.map { |bucket| bucket.slice(:key, :label, :color).merge(count: 0) },
        observed_count: 0,
        estimated_count: 0,
      },
      reserve_runway: {
        summary: "No reserve runway rows available for this route.",
        cards: [],
        observed_count: 0,
        estimated_count: 0,
      },
      downstream_pathway: {
        summary: "No downstream pathway is available for this route yet.",
        stages: [],
      },
    }
  end

  def exposure_rows
    CountryChokepointExposure
      .where(chokepoint_key: @chokepoint_key, commodity_key: @commodity_key)
      .order(exposure_score: :desc, dependency_score: :desc, supplier_share_pct: :desc)
      .to_a
  end

  def build_dependency_rows(exposures)
    return [] if exposures.blank?

    dependencies = CountryCommodityDependency
      .where(country_code_alpha3: exposures.map(&:country_code_alpha3), commodity_key: @commodity_key)
      .index_by(&:country_code_alpha3)

    exposures.map do |exposure|
      dependency = dependencies[exposure.country_code_alpha3]
      estimated = estimated_row?(exposure) || estimated_row?(dependency)
      bucket = dependency_bucket(exposure.exposure_score)

      {
        country_code_alpha3: exposure.country_code_alpha3,
        country_name: exposure.country_name,
        exposure_score: exposure.exposure_score.to_f,
        dependency_score: first_present_decimal(exposure.dependency_score, dependency&.dependency_score),
        supplier_share_pct: exposure.supplier_share_pct&.to_f,
        import_share_gdp_pct: dependency&.import_share_gdp_pct&.to_f,
        supplier_count: dependency&.supplier_count,
        estimated: estimated,
        bucket: bucket.fetch(:key),
        bucket_label: bucket.fetch(:label),
        bucket_color: bucket.fetch(:color),
      }
    end.first(DISPLAY_ROW_LIMIT)
  end

  def build_dependency_map(rows)
    all_rows = exposure_rows.map do |exposure|
      estimated = estimated_row?(exposure)
      bucket = dependency_bucket(exposure.exposure_score)
      {
        exposure_score: exposure.exposure_score.to_f,
        estimated: estimated,
        bucket: bucket.fetch(:key),
      }
    end

    {
      summary: dependency_map_summary(rows, all_rows),
      rows: rows,
      buckets: DEPENDENCY_BUCKETS.map do |bucket|
        {
          key: bucket.fetch(:key),
          label: bucket.fetch(:label),
          color: bucket.fetch(:color),
          count: all_rows.count { |row| row[:bucket] == bucket.fetch(:key) },
        }
      end,
      observed_count: all_rows.count { |row| row[:estimated] == false },
      estimated_count: all_rows.count { |row| row[:estimated] == true },
    }
  end

  def dependency_map_summary(rows, all_rows)
    return "No dependency rows available for this route." if rows.blank?

    top = rows.first
    critical_count = all_rows.count { |row| row[:bucket] == "critical" }
    estimate_label = top[:estimated] ? "estimated" : "observed"

    "#{critical_count} critical countries; strongest #{top[:country_name]} #{format('%.2f', top[:exposure_score])} #{estimate_label}."
  end

  def latest_energy_metrics_by_country(country_codes)
    return {} if country_codes.blank?

    EnergyBalanceSnapshot
      .where(country_code_alpha3: country_codes, commodity_key: @commodity_key)
      .order(period_start: :desc, updated_at: :desc)
      .to_a
      .group_by(&:country_code_alpha3)
      .transform_values do |rows|
        rows.each_with_object({}) do |row, memo|
          memo[row.metric_key] ||= row.value_numeric&.to_f
        end
      end
  end

  def build_reserve_runway(rows, metrics_by_country)
    cards = rows.filter_map do |row|
      metrics = metrics_by_country[row[:country_code_alpha3]] || {}
      stock_days = metrics["stocks_days"]
      closing_stock = metrics["closing_stock_convbbl"]
      imports_kbd = metrics["imports_kbd"]
      direct_use_kbd = metrics["direct_use_kbd"]
      supplier_fraction = row[:supplier_share_pct].to_f / 100.0
      runway_days, basis = derive_runway_days(
        stock_days: stock_days,
        closing_stock: closing_stock,
        imports_kbd: imports_kbd,
        direct_use_kbd: direct_use_kbd,
        supplier_fraction: supplier_fraction,
      )
      next unless runway_days

      coverage_mode = runway_coverage_mode(row[:estimated], stock_days, basis)
      {
        country_code_alpha3: row[:country_code_alpha3],
        country_name: row[:country_name],
        runway_days: runway_days.round,
        stock_days: stock_days&.round,
        supplier_share_pct: row[:supplier_share_pct]&.round(1),
        coverage_mode: coverage_mode,
        basis: basis,
        status: runway_status(runway_days),
      }
    end.sort_by { |card| card[:runway_days] }.first(RUNWAY_CARD_LIMIT)

    {
      summary: reserve_runway_summary(cards),
      cards: cards,
      observed_count: cards.count { |card| card[:coverage_mode] == "observed" },
      estimated_count: cards.count { |card| card[:coverage_mode] == "estimated" },
    }
  end

  def reserve_runway_summary(cards)
    return "No reserve runway rows available for this route." if cards.blank?

    shortest = cards.first
    "#{shortest[:country_name]} is the shortest runway at #{shortest[:runway_days]} days; #{cards.count} countries have usable storage data."
  end

  def build_downstream_pathway(dependency_map, reserve_runway)
    top_dependency = dependency_map[:rows].first
    shortest_runway = reserve_runway[:cards].first
    flow = chokepoint_flow
    stages = downstream_templates.map do |template|
      {
        phase: template.fetch(:phase),
        title: template.fetch(:title),
        description: downstream_stage_description(template.fetch(:key), top_dependency, shortest_runway, flow),
        stats: downstream_stage_stats(template.fetch(:key), top_dependency, shortest_runway, flow),
      }
    end

    {
      summary: downstream_pathway_summary(top_dependency, shortest_runway, flow),
      stages: stages,
    }
  end

  def downstream_pathway_summary(top_dependency, shortest_runway, flow)
    parts = []
    parts << "#{chokepoint_name} carries #{flow[:pct]}% of world #{flow[:label]}" if flow[:pct]
    parts << "#{top_dependency[:country_name]} is the most exposed importer" if top_dependency
    parts << "#{shortest_runway[:country_name]} has #{shortest_runway[:runway_days]} days of cover" if shortest_runway
    parts.join(" · ").presence || "Derived downstream stages are available for this route."
  end

  def downstream_templates
    case @commodity_key
    when "oil_crude", "oil_refined"
      [
        { key: "shock", phase: "Day 1", title: "Crude and product shock" },
        { key: "refining", phase: "Week 1", title: "Refining and fuel drawdown" },
        { key: "industry", phase: "Weeks 2-4", title: "Freight and industrial pass-through" },
        { key: "consumer", phase: "Months 2-3", title: "Food and inflation pressure" },
      ]
    when "lng", "gas_nat"
      [
        { key: "shock", phase: "Day 1", title: "LNG cargo shock" },
        { key: "power", phase: "Week 1", title: "Power and utilities drawdown" },
        { key: "industry", phase: "Weeks 2-4", title: "Industrial feedstock rationing" },
        { key: "consumer", phase: "Months 2-3", title: "Power tariffs and inflation" },
      ]
    else
      [
        { key: "shock", phase: "Day 1", title: "Route disruption" },
        { key: "industry", phase: "Week 1", title: "Factory and logistics stress" },
        { key: "consumer", phase: "Weeks 2-4", title: "Downstream consumer pressure" },
      ]
    end
  end

  def downstream_stage_description(stage_key, top_dependency, shortest_runway, flow)
    case stage_key
    when "shock"
      [
        flow[:volume],
        flow[:note],
        top_dependency ? "#{top_dependency[:country_name]} sits in the highest exposure tier." : nil,
      ].compact.join(" ")
    when "refining", "power"
      [
        shortest_runway ? "#{shortest_runway[:country_name]} only has #{shortest_runway[:runway_days]} days of modeled cover." : nil,
        top_dependency ? "#{top_dependency[:country_name]} remains the strongest dependency row." : nil,
      ].compact.join(" ")
    when "industry"
      [
        "Input costs travel through freight, heavy industry, and strategic shipping lanes.",
        flow[:pct] ? "#{flow[:pct]}% of world #{flow[:label]} passes this route." : nil,
      ].compact.join(" ")
    when "consumer"
      "Costs pass into consumer fuel, food logistics, and inflation baskets once inventories tighten."
    else
      "Derived downstream stage."
    end
  end

  def downstream_stage_stats(stage_key, top_dependency, shortest_runway, flow)
    case stage_key
    when "shock"
      [flow[:pct] ? "#{flow[:pct]}% global flow" : nil, flow[:volume], flow[:label].presence].compact
    when "refining", "power"
      [
        shortest_runway ? "#{shortest_runway[:country_name]} #{shortest_runway[:runway_days]} days" : nil,
        top_dependency ? "#{top_dependency[:country_name]} exposure #{format('%.2f', top_dependency[:exposure_score])}" : nil,
      ].compact
    when "industry"
      [
        top_dependency ? "#{top_dependency[:country_name]} import GDP #{format('%.2f', top_dependency[:import_share_gdp_pct].to_f)}%" : nil,
        top_dependency&.[](:supplier_share_pct) ? "#{format('%.1f', top_dependency[:supplier_share_pct])}% supplier share" : nil,
      ].compact
    when "consumer"
      [
        shortest_runway ? "Runway basis #{shortest_runway[:basis].tr('_', ' ')}" : nil,
        top_dependency&.[](:bucket_label) ? "#{top_dependency[:bucket_label]} dependency tier" : nil,
      ].compact
    else
      []
    end
  end

  def derive_runway_days(stock_days:, closing_stock:, imports_kbd:, direct_use_kbd:, supplier_fraction:)
    supplier_fraction = supplier_fraction.clamp(0.0, 1.0)
    if stock_days.to_f.positive?
      divisor = supplier_fraction.positive? ? supplier_fraction : 1.0
      return [(stock_days.to_f / divisor).clamp(0.0, MAX_RUNWAY_DAYS), supplier_fraction.positive? ? "stock_days_adjusted" : "stock_days"]
    end

    reference_rate = if imports_kbd.to_f.positive? && supplier_fraction.positive?
      imports_kbd.to_f * supplier_fraction
    elsif imports_kbd.to_f.positive?
      imports_kbd.to_f
    else
      direct_use_kbd.to_f
    end

    return [nil, nil] unless closing_stock.to_f.positive? && reference_rate.positive?

    [(closing_stock.to_f / reference_rate).clamp(0.0, MAX_RUNWAY_DAYS), "stock_volume"]
  end

  def runway_status(runway_days)
    return "critical" if runway_days < 30
    return "high" if runway_days < 90
    return "medium" if runway_days < 180

    "low"
  end

  def runway_coverage_mode(row_estimated, stock_days, basis)
    return "estimated" if row_estimated && stock_days.blank? && basis.blank?
    return "mixed" if row_estimated
    return "observed" if stock_days.present? || basis.present?

    "estimated"
  end

  def dependency_bucket(score)
    value = score.to_f
    DEPENDENCY_BUCKETS.find { |bucket| value >= bucket.fetch(:min) } || DEPENDENCY_BUCKETS.last
  end

  def commodity_name
    SupplyChainCatalog.commodity_name_for(@commodity_key) || @commodity_key.to_s.humanize
  end

  def chokepoint_name
    ChokepointMonitorService::CHOKEPOINTS.dig(@chokepoint_key.to_sym, :name) || @chokepoint_key.to_s.humanize
  end

  def chokepoint_flow
    flow_type = SupplyChainCatalog.commodity_flow_type_for(@commodity_key)
    flow = ChokepointMonitorService::CHOKEPOINTS.dig(@chokepoint_key.to_sym, :flows, flow_type) || {}
    {
      label: flow_type.to_s.tr("_", " "),
      pct: flow[:pct],
      volume: flow[:volume],
      note: flow[:note],
    }
  end

  def estimated_row?(row)
    metadata = row&.metadata || {}
    metadata["estimated"] == true || metadata[:estimated] == true
  end

  def first_present_decimal(*values)
    values.each do |value|
      next if value.nil?
      return value.to_f
    end
    nil
  end
end
