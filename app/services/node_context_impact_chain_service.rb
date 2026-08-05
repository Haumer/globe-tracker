class NodeContextImpactChainService
  MAX_CHAINS = 6
  MAX_MARKET_BENCHMARKS = 3

  STRUCTURAL_COMMODITY_KEYS = %w[
    commodity:gas_nat
    commodity:lng
    commodity:oil_crude
    commodity:oil_refined
  ].freeze

  BENCHMARK_GROUPS = {
    "commodity:oil_crude" => %w[commodity:oil_brent commodity:oil_wti],
    "commodity:oil_refined" => %w[commodity:oil_brent commodity:oil_wti],
    "commodity:gas_nat" => %w[commodity:gas_nat commodity:lng],
    "commodity:lng" => %w[commodity:lng commodity:gas_nat],
  }.freeze
  BENCHMARK_SYMBOLS = {
    "commodity:oil_brent" => "OIL_BRENT",
    "commodity:oil_wti" => "OIL_WTI",
    "commodity:gas_nat" => "GAS_NAT",
    "commodity:lng" => "LNG",
  }.freeze

  class << self
    def for(node)
      new(node).call
    rescue ActiveRecord::StatementInvalid
      []
    end
  end

  def initialize(node)
    @node = node
    @commodity_cache = {}
  end

  def call
    return [] unless @node.is_a?(OntologyEntity)

    chains = case @node.entity_type
    when "theater"
      chains_for_theater(@node)
    when "corridor"
      chains_for_corridor(@node, pressure_relationships: incoming_theater_pressure(@node).first(3))
    when "country"
      chains_for_country(@node)
    when "commodity"
      chains_for_commodity(@node)
    else
      []
    end

    chains
      .compact
      .uniq { |chain| chain[:id] }
      .sort_by { |chain| [-chain[:score].to_i, chain[:title].to_s] }
      .then { |sorted| diversify_chains(sorted) }
      .first(MAX_CHAINS)
  end

  private

  def chains_for_theater(theater)
    theater.outgoing_ontology_relationships.active
      .includes(:target_node, :ontology_relationship_evidences)
      .where(relation_type: "theater_pressure", target_node_type: "OntologyEntity")
      .order(confidence: :desc, updated_at: :desc)
      .flat_map do |relationship|
        target = relationship.target_node
        next [] unless corridor_entity?(target)

        chains_for_corridor(target, pressure_relationships: [relationship])
      end
  end

  def chains_for_corridor(corridor, pressure_relationships: [])
    flow_relationships = flow_relationships_for(corridor)
    structural_flows = flow_relationships.select { |relationship| structural_commodity?(relationship.target_node) }
    benchmark_flows = flow_relationships - structural_flows
    pressure = pressure_relationships.first

    chokepoint_exposures_for(corridor).flat_map do |exposure|
      country = exposure.target_node
      next [] unless country_entity?(country)

      matched_flows = flows_matching_exposure(structural_flows, exposure)
      representative_flows(matched_flows).map do |flow|
        build_route_chain(
          pressure: pressure,
          corridor: corridor,
          flow: flow,
          country: country,
          exposure: exposure,
          benchmark_flows: benchmark_flows,
        )
      end
    end
  end

  def chains_for_country(country)
    chokepoint_exposures_for_country(country).flat_map do |exposure|
      corridor = exposure.source_node
      next [] unless corridor_entity?(corridor)

      pressure = incoming_theater_pressure(corridor).first
      flow_relationships = flow_relationships_for(corridor)
      structural_flows = flow_relationships.select { |relationship| structural_commodity?(relationship.target_node) }
      benchmark_flows = flow_relationships - structural_flows

      representative_flows(flows_matching_exposure(structural_flows, exposure)).map do |flow|
        build_route_chain(
          pressure: pressure,
          corridor: corridor,
          flow: flow,
          country: country,
          exposure: exposure,
          benchmark_flows: benchmark_flows,
        )
      end
    end
  end

  def chains_for_commodity(commodity)
    corridors = commodity.incoming_ontology_relationships.active
      .includes(:source_node)
      .where(relation_type: "flow_dependency", source_node_type: "OntologyEntity")
      .order(confidence: :desc, updated_at: :desc)
      .map(&:source_node)
      .select { |entity| corridor_entity?(entity) }

    corridors.flat_map do |corridor|
      flow_relationship = corridor.outgoing_ontology_relationships.active
        .where(relation_type: "flow_dependency", target_node: commodity)
        .first
      next [] unless flow_relationship

      chains_for_corridor(corridor, pressure_relationships: incoming_theater_pressure(corridor).first(1))
        .select { |chain| chain.dig(:focus, :commodity_key) == commodity.canonical_key }
    end
  end

  def build_route_chain(pressure:, corridor:, flow:, country:, exposure:, benchmark_flows:)
    commodity = flow.target_node
    import_dependency = import_dependency_for(commodity, country)
    sector_dependency = sector_dependency_for(commodity, country)
    market_benchmarks = market_benchmarks_for(commodity, benchmark_flows)
    score = impact_score(pressure, flow, exposure, import_dependency, sector_dependency, market_benchmarks)
    severity = severity_for(score, market_benchmarks)

    driver = pressure&.source_node
    sector = sector_dependency&.target_node
    title = [
      driver&.canonical_name,
      corridor.canonical_name,
      commodity.canonical_name,
      country.canonical_name,
    ].compact.join(" -> ")

    {
      id: [
        "impact-chain",
        driver&.canonical_key || "structural",
        corridor.canonical_key,
        commodity.canonical_key,
        country.canonical_key,
      ].join(":"),
      kind: "route_market_country_exposure",
      severity: severity,
      score: score,
      confidence: chain_confidence(pressure, flow, exposure, import_dependency, sector_dependency),
      title: title,
      summary: summary_for(
        pressure: pressure,
        corridor: corridor,
        flow: flow,
        commodity: commodity,
        country: country,
        exposure: exposure,
        import_dependency: import_dependency,
        sector_dependency: sector_dependency,
        market_benchmarks: market_benchmarks,
      ),
      focus: {
        corridor_key: corridor.canonical_key,
        commodity_key: commodity.canonical_key,
        country_key: country.canonical_key,
      },
      steps: chain_steps(
        driver: driver,
        pressure: pressure,
        corridor: corridor,
        flow: flow,
        commodity: commodity,
        country: country,
        exposure: exposure,
        sector: sector,
        sector_dependency: sector_dependency,
      ),
      metrics: chain_metrics(flow, exposure, import_dependency, sector_dependency, market_benchmarks),
      evidence: chain_evidence(pressure, flow, exposure, import_dependency),
    }
  end

  def incoming_theater_pressure(corridor)
    corridor.incoming_ontology_relationships.active
      .includes(:source_node, :ontology_relationship_evidences)
      .where(relation_type: "theater_pressure", source_node_type: "OntologyEntity")
      .order(confidence: :desc, updated_at: :desc)
      .select { |relationship| relationship.source_node&.entity_type == "theater" }
  end

  def flow_relationships_for(corridor)
    corridor.outgoing_ontology_relationships.active
      .includes(:target_node, :ontology_relationship_evidences)
      .where(relation_type: "flow_dependency", target_node_type: "OntologyEntity")
      .order(confidence: :desc, updated_at: :desc)
      .select { |relationship| relationship.target_node&.entity_type == "commodity" }
  end

  def chokepoint_exposures_for(corridor)
    corridor.outgoing_ontology_relationships.active
      .includes(:target_node, :ontology_relationship_evidences)
      .where(relation_type: "chokepoint_exposure", target_node_type: "OntologyEntity")
      .order(confidence: :desc, updated_at: :desc)
      .select { |relationship| country_entity?(relationship.target_node) }
  end

  def chokepoint_exposures_for_country(country)
    country.incoming_ontology_relationships.active
      .includes(:source_node, :ontology_relationship_evidences)
      .where(relation_type: "chokepoint_exposure", source_node_type: "OntologyEntity")
      .order(confidence: :desc, updated_at: :desc)
      .select { |relationship| corridor_entity?(relationship.source_node) }
  end

  def flows_matching_exposure(flows, exposure)
    keys = exposure_commodity_keys(exposure)
    matches = flows.select { |relationship| keys.include?(relationship.target_node&.canonical_key) }
    matches.presence || flows
  end

  def representative_flows(flows)
    flows
      .group_by { |relationship| commodity_group(relationship.target_node&.canonical_key) }
      .values
      .filter_map { |grouped| grouped.max_by(&:confidence) }
      .sort_by { |relationship| [commodity_group_priority(relationship.target_node&.canonical_key), -relationship.confidence.to_f] }
      .first(2)
  end

  def diversify_chains(sorted_chains)
    selected = []
    %w[oil gas other].each do |group|
      chain = sorted_chains.find { |candidate| commodity_group(candidate.dig(:focus, :commodity_key)) == group }
      selected << chain if chain
    end

    (selected + sorted_chains)
      .compact
      .uniq { |chain| chain[:id] }
  end

  def exposure_commodity_keys(exposure)
    Array(metadata_for(exposure)["commodities"]).filter_map do |key|
      key = key.to_s
      next if key.blank?

      key.start_with?("commodity:") ? key : "commodity:#{key}"
    end
  end

  def import_dependency_for(commodity, country)
    candidates = commodity_equivalents(commodity).flat_map do |candidate|
      candidate.outgoing_ontology_relationships.active
        .where(relation_type: "import_dependency", target_node: country)
        .to_a
    end

    candidates.max_by(&:confidence)
  end

  def sector_dependency_for(commodity, country)
    country_code = country.canonical_key.to_s.split(":").last
    sector_scope = OntologyEntity.where("canonical_key LIKE ?", "sector:#{country_code}:%")
    sector_ids = sector_scope.pluck(:id)
    return unless sector_ids.any?

    commodity_equivalents(commodity).flat_map do |candidate|
      candidate.outgoing_ontology_relationships.active
        .includes(:target_node)
        .where(
          relation_type: "production_dependency",
          target_node_type: "OntologyEntity",
          target_node_id: sector_ids,
        )
        .to_a
    end.max_by(&:confidence)
  end

  def commodity_equivalents(commodity)
    keys = [commodity.canonical_key]
    case commodity.canonical_key
    when "commodity:oil_wti", "commodity:oil_brent"
      keys << "commodity:oil_crude"
    when "commodity:oil_crude"
      keys.concat(%w[commodity:oil_wti commodity:oil_brent])
    when "commodity:lng"
      keys << "commodity:gas_nat"
    when "commodity:gas_nat"
      keys << "commodity:lng"
    end

    keys.uniq.filter_map { |key| commodity_for_key(key) }
  end

  def commodity_for_key(key)
    @commodity_cache[key] ||= OntologyEntity.find_by(canonical_key: key)
  end

  def market_benchmarks_for(commodity, benchmark_flows)
    keys = BENCHMARK_GROUPS.fetch(commodity.canonical_key, [commodity.canonical_key])
    from_flow_relationships = benchmark_flows
      .select { |relationship| keys.include?(relationship.target_node&.canonical_key) }
      .map { |relationship| benchmark_payload(relationship) }
      .compact
      .first(MAX_MARKET_BENCHMARKS)

    return from_flow_relationships if from_flow_relationships.any?

    keys.filter_map { |key| benchmark_payload_for_key(key) }.first(MAX_MARKET_BENCHMARKS)
  end

  def benchmark_payload(relationship)
    commodity = relationship.target_node
    return unless commodity

    relationship_metadata = metadata_for(relationship)
    commodity_metadata = metadata_for(commodity)
    latest_change = relationship_metadata["latest_change_pct"] || commodity_metadata["change_pct"]
    {
      name: commodity.canonical_name,
      key: commodity.canonical_key,
      symbol: relationship_metadata["commodity_symbol"] || commodity_metadata["symbol"],
      latest_price: relationship_metadata["latest_price"] || commodity_metadata["latest_price"],
      latest_change_pct: latest_change,
      flow_pct: relationship_metadata["flow_pct"] || relationship_metadata["flow_share_pct"],
    }.compact
  end

  def benchmark_payload_for_key(key)
    commodity = commodity_for_key(key)
    symbol = metadata_for(commodity)["symbol"].presence || BENCHMARK_SYMBOLS[key]
    price = latest_price_for_symbol(symbol)
    commodity_metadata = metadata_for(commodity)

    {
      name: commodity&.canonical_name || symbol || key.to_s.sub(/\Acommodity:/, "").tr("_", " ").titleize,
      key: key,
      symbol: symbol,
      latest_price: price&.price || commodity_metadata["latest_price"],
      latest_change_pct: price&.change_pct || commodity_metadata["change_pct"],
    }.compact
  end

  def latest_price_for_symbol(symbol)
    return if symbol.blank?

    CommodityPrice.where(symbol: symbol).order(recorded_at: :desc).first
  rescue ActiveRecord::StatementInvalid
    nil
  end

  def chain_steps(driver:, pressure:, corridor:, flow:, commodity:, country:, exposure:, sector:, sector_dependency:)
    [
      driver && {
        role: "driver",
        relation_type: pressure.relation_type,
        label: driver.canonical_name,
        node: node_payload(driver),
        detail: pressure.explanation,
      },
      {
        role: "corridor",
        relation_type: flow.relation_type,
        label: corridor.canonical_name,
        node: node_payload(corridor),
        detail: flow.explanation,
      },
      {
        role: "flow",
        relation_type: flow.relation_type,
        label: commodity.canonical_name,
        node: node_payload(commodity),
        detail: commodity_detail(flow, commodity),
      },
      {
        role: "exposure",
        relation_type: exposure.relation_type,
        label: country.canonical_name,
        node: node_payload(country),
        detail: exposure.explanation,
      },
      sector && {
        role: "economic_channel",
        relation_type: sector_dependency.relation_type,
        label: sector.canonical_name,
        node: node_payload(sector),
        detail: sector_dependency.explanation,
      },
    ].compact
  end

  def chain_metrics(flow, exposure, import_dependency, sector_dependency, market_benchmarks)
    exposure_metadata = metadata_for(exposure)
    import_metadata = metadata_for(import_dependency)
    sector_metadata = metadata_for(sector_dependency&.target_node)
    [
      flow_share_metric(flow),
      exposure_metadata["max_exposure_score"].present? && {
        label: "Route exposure",
        value: exposure_metadata["max_exposure_score"].to_f.round(2).to_s,
      },
      import_metadata["dependency_score"].present? && {
        label: "Import dependency",
        value: import_metadata["dependency_score"].to_f.round(2).to_s,
      },
      sector_metadata["share_pct"].present? && {
        label: "Sector GDP share",
        value: "#{sector_metadata["share_pct"].to_f.round(1)}%",
      },
      *market_benchmarks.map { |benchmark| market_metric(benchmark) },
    ].compact
  end

  def chain_evidence(*relationships)
    relationships.compact.flat_map do |relationship|
      relationship.ontology_relationship_evidences.first(2).filter_map do |evidence_link|
        evidence = load_evidence_record(evidence_link)
        serialized = evidence ? NodeContextEvidenceSerializer.serialize(evidence) : nil
        next unless serialized

        serialized.slice(:type, :id, :label, :meta, :url).merge(
          role: evidence_link.evidence_role,
          confidence: evidence_link.confidence.to_f.round(2),
        )
      end
    end.uniq { |evidence| [evidence[:type], evidence[:id], evidence[:role]] }.first(4)
  end

  def summary_for(pressure:, corridor:, flow:, commodity:, country:, exposure:, import_dependency:, sector_dependency:, market_benchmarks:)
    parts = []
    if pressure&.source_node
      parts << "#{pressure.source_node.canonical_name} is pressuring #{corridor.canonical_name}"
    else
      parts << "#{corridor.canonical_name} is modeled as a route dependency"
    end
    parts << "for #{commodity.canonical_name}"
    parts << "with downstream exposure in #{country.canonical_name}"

    if import_dependency
      parts << "and a country import-dependency edge"
    elsif metadata_for(exposure)["commodities"].present?
      parts << "based on estimated chokepoint exposure"
    end

    if sector_dependency&.target_node
      parts << "touching #{sector_dependency.target_node.canonical_name}"
    end

    benchmark_text = market_benchmarks.filter_map { |benchmark| market_change_label(benchmark) }.join(", ")
    parts << "Current benchmark signal: #{benchmark_text}" if benchmark_text.present?

    "#{parts.join("; ")}."
  end

  def flow_share_metric(flow)
    flow_metadata = metadata_for(flow)
    flow_pct = flow_metadata["flow_pct"] || flow_metadata["flow_share_pct"]
    return unless flow_pct.present?

    {
      label: "Global flow",
      value: "#{flow_pct.to_f.round(1)}%",
    }
  end

  def market_metric(benchmark)
    label = benchmark[:symbol].presence || benchmark[:name]
    value = market_change_label(benchmark)
    return unless label.present? && value.present?

    {
      label: label,
      value: value,
    }
  end

  def market_change_label(benchmark)
    change = benchmark[:latest_change_pct]
    return if change.blank?

    value = change.to_f
    "#{value.positive? ? "+" : ""}#{value.round(2)}%"
  end

  def commodity_detail(flow, commodity)
    flow_metadata = metadata_for(flow)
    flow_pct = flow_metadata["flow_pct"] || flow_metadata["flow_share_pct"]
    return flow.explanation if flow.explanation.present?
    return "#{commodity.canonical_name} flow share: #{flow_pct}%" if flow_pct.present?

    metadata_for(commodity)["description"]
  end

  def impact_score(pressure, flow, exposure, import_dependency, sector_dependency, market_benchmarks)
    score = 0
    score += pressure.confidence.to_f * 32 if pressure
    score += flow.confidence.to_f * 24 if flow
    score += exposure.confidence.to_f * 22 if exposure
    score += import_dependency.confidence.to_f * 14 if import_dependency
    score += sector_dependency.confidence.to_f * 8 if sector_dependency
    score += 6 if max_abs_market_move(market_benchmarks) >= 5
    [score.round, 99].min
  end

  def severity_for(score, market_benchmarks)
    return "critical" if score >= 86 && max_abs_market_move(market_benchmarks) >= 5
    return "high" if score >= 70
    return "medium" if score >= 50

    "low"
  end

  def chain_confidence(*relationships)
    values = relationships.compact.map { |relationship| relationship.confidence.to_f }
    return 0 if values.empty?

    (values.sum / values.size).round(2)
  end

  def max_abs_market_move(market_benchmarks)
    market_benchmarks.map { |benchmark| benchmark[:latest_change_pct].to_f.abs }.max || 0
  end

  def commodity_group(commodity_key)
    case commodity_key
    when "commodity:oil_crude", "commodity:oil_refined", "commodity:oil_wti", "commodity:oil_brent"
      "oil"
    when "commodity:gas_nat", "commodity:lng"
      "gas"
    else
      "other"
    end
  end

  def commodity_group_priority(commodity_key)
    {
      "oil" => 0,
      "gas" => 1,
      "other" => 2,
    }.fetch(commodity_group(commodity_key), 2)
  end

  def node_payload(node)
    {
      node_type: "entity",
      id: node.id,
      canonical_key: node.canonical_key,
      entity_type: node.entity_type,
      name: node.canonical_name,
      request: node_request_for(node),
    }.compact
  end

  def node_request_for(node)
    case node.entity_type
    when "theater"
      { kind: "theater", id: node.canonical_key.to_s.sub(/\Atheater:/, "") }
    when "corridor"
      if node.canonical_key.to_s.start_with?("corridor:chokepoint:")
        { kind: "chokepoint", id: node.canonical_key.to_s.split(":").last }
      else
        { kind: "entity", id: node.canonical_key }
      end
    when "commodity"
      { kind: "commodity", id: node.canonical_key }
    else
      { kind: "entity", id: node.canonical_key }
    end
  end

  def load_evidence_record(link)
    klass = link.evidence_type.to_s.safe_constantize
    klass.find_by(id: link.evidence_id) if klass&.respond_to?(:find_by)
  rescue StandardError
    nil
  end

  def metadata_for(record)
    record&.metadata.presence || {}
  end

  def corridor_entity?(node)
    node.is_a?(OntologyEntity) && node.entity_type == "corridor"
  end

  def country_entity?(node)
    node.is_a?(OntologyEntity) && node.entity_type == "country"
  end

  def structural_commodity?(node)
    node.is_a?(OntologyEntity) && STRUCTURAL_COMMODITY_KEYS.include?(node.canonical_key)
  end
end
