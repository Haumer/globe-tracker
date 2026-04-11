class SituationAssessmentService
  RECENT_WINDOW = 24.hours
  MAX_ITEMS = 6
  EXCLUDED_RECENT_ENTITY_TYPES = %w[asset source].freeze
  REPORTED_EVIDENCE_TYPES = %w[news_story_cluster news_article].freeze
  OBSERVED_EVIDENCE_TYPES = %w[
    camera
    commodity_price
    earthquake
    fire_hotspot
    flight
    gps_jamming_snapshot
    internet_outage
    natural_event
    notam
    ship
  ].freeze
  OBSERVED_RELATIONSHIP_TYPES = %w[operational_activity local_corroboration].freeze
  ACTIONABLE_RELATIONSHIP_TYPES = %w[infrastructure_disruption infrastructure_exposure operational_activity local_corroboration theater_pressure].freeze
  INFERRED_RELATIONSHIP_TYPES = %w[
    chokepoint_exposure
    downstream_exposure
    economic_profile
    flow_dependency
    infrastructure_disruption
    infrastructure_exposure
    import_dependency
    production_dependency
    theater_pressure
  ].freeze

  class << self
    def for_node(kind:, id:, now: Time.current)
      new(now: now).for_node(kind: kind, id: id)
    end

    def recent(limit: 12, now: Time.current)
      new(now: now).recent(limit: limit)
    end
  end

  def initialize(now:)
    @now = now
  end

  def for_node(kind:, id:)
    context = NodeContextService.resolve(kind: kind, id: id).deep_symbolize_keys
    build_assessment(context: context, request_kind: kind, request_id: id)
  end

  def recent(limit:)
    limit = limit.to_i.clamp(1, 24)
    requests = recent_requests(limit: limit)

    assessments = []
    requests.each do |request|
      assessment = for_node(**request)
      next unless actionable_assessment?(assessment)

      assessments << assessment
      break if assessments.size >= limit
    rescue NodeContextService::NodeNotFoundError, NodeContextService::UnsupportedNodeError
      nil
    end
    assessments
  end

  private

  def recent_requests(limit:)
    requests = recent_event_requests(limit: limit) + recent_relationship_node_requests(limit: limit)
    requests.uniq { |request| [request[:kind], request[:id]] }.first(limit * 8)
  end

  def recent_event_requests(limit:)
    OntologyEvent
      .where("last_seen_at >= ?", @now - RECENT_WINDOW)
      .order(last_seen_at: :desc, updated_at: :desc)
      .limit(limit * 3)
      .filter_map { |event| request_for_node(event) }
  end

  def recent_relationship_node_requests(limit:)
    OntologyRelationship.active
      .includes(:source_node, :target_node)
      .order(confidence: :desc, updated_at: :desc)
      .limit(limit * 10)
      .flat_map { |relationship| [relationship.target_node, relationship.source_node] }
      .filter_map { |node| request_for_node(node) }
  end

  def request_for_node(node)
    case node
    when OntologyEntity
      return if EXCLUDED_RECENT_ENTITY_TYPES.include?(node.entity_type)

      { kind: "entity", id: node.canonical_key }
    when OntologyEvent
      key = node.canonical_key.to_s
      if key.start_with?("news-story-cluster:")
        return { kind: "news_story_cluster", id: key.delete_prefix("news-story-cluster:") }
      end

      { kind: "event", id: key }
    end
  end

  def build_assessment(context:, request_kind:, request_id:)
    node = context.fetch(:node)
    relationships = Array(context[:relationships])
    direct_evidence = Array(context[:evidence])
    relationship_evidence = relationships.flat_map { |relationship| Array(relationship[:evidence]) }
    evidence = unique_evidence(direct_evidence + relationship_evidence)
    observed = observed_items(relationships: relationships, evidence: evidence)
    reported = reported_items(evidence)
    inferred = inferred_items(relationships)
    missing = missing_data(node: node, context: context, relationships: relationships, evidence: evidence, observed: observed, reported: reported)
    situation_type = situation_type_for(node, relationships: relationships)

    {
      assessment_key: "#{request_kind}:#{request_id}",
      situation_type: situation_type,
      title: node[:name],
      summary: summary_for(node: node, situation_type: situation_type, relationships: relationships, observed: observed, reported: reported, inferred: inferred),
      node: node,
      confidence: confidence_for(relationships: relationships, evidence: evidence, missing_data: missing),
      coverage_quality: coverage_quality(node: node, context: context, relationships: relationships, evidence: evidence, observed: observed, reported: reported),
      observed: observed.first(MAX_ITEMS),
      reported: reported.first(MAX_ITEMS),
      inferred: inferred.first(MAX_ITEMS),
      missing_data: missing.first(MAX_ITEMS),
      watch_next: watch_next_for(situation_type: situation_type, relationships: relationships).first(MAX_ITEMS),
      affected_entities: affected_entities(relationships).first(MAX_ITEMS),
      evidence: evidence.first(MAX_ITEMS * 2),
      relationships: relationships.first(MAX_ITEMS * 2),
      generated_at: @now.iso8601,
    }
  end

  def observed_items(relationships:, evidence:)
    relationship_observations = relationships
      .select { |relationship| OBSERVED_RELATIONSHIP_TYPES.include?(relationship[:relation_type].to_s) }
      .filter_map { |relationship| relationship_explanation(relationship) }

    evidence_observations = evidence
      .select { |item| OBSERVED_EVIDENCE_TYPES.include?(item[:type].to_s) }
      .filter_map { |item| evidence_sentence(item) }

    unique_strings(relationship_observations + evidence_observations)
  end

  def reported_items(evidence)
    evidence
      .select { |item| REPORTED_EVIDENCE_TYPES.include?(item[:type].to_s) }
      .filter_map { |item| evidence_sentence(item) }
      .then { |items| unique_strings(items) }
  end

  def inferred_items(relationships)
    relationships
      .select { |relationship| INFERRED_RELATIONSHIP_TYPES.include?(relationship[:relation_type].to_s) }
      .filter_map { |relationship| relationship_explanation(relationship) }
      .then { |items| unique_strings(items) }
  end

  def relationship_explanation(relationship)
    explanation = relationship[:explanation].presence
    return explanation if explanation.present?

    node_name = relationship.dig(:node, :name)
    return if node_name.blank?

    "#{relationship[:relation_type].to_s.tr("_", " ")} relationship with #{node_name}"
  end

  def evidence_sentence(item)
    label = item[:label].presence
    return if label.blank?

    meta = item[:meta].presence
    role = item[:role].presence
    suffix = [role, meta].compact.join(" · ")
    suffix.present? ? "#{label} (#{suffix})" : label
  end

  def missing_data(node:, context:, relationships:, evidence:, observed:, reported:)
    missing = []
    missing << "No active graph relationships attached to this node" if relationships.empty?
    missing << "No direct reporting evidence attached" if reported.empty?
    missing << "No live operational evidence attached" if observed.empty?
    missing << "No geographic coordinates attached to the node" if node[:latitude].blank? || node[:longitude].blank?
    missing << "No actor or affected-entity memberships attached" if node[:node_type] == "event" && Array(context[:memberships]).empty?
    missing << "No evidence links attached to this node" if evidence.empty?
    missing
  end

  def watch_next_for(situation_type:, relationships:)
    relation_types = relationships.map { |relationship| relationship[:relation_type].to_s }.uniq

    case situation_type
    when "conflict_report", "theater_assessment", "corridor_exposure"
      [
        "new corroborated reporting tied to this node",
        "operational_activity edges from flights, ships, NOTAMs, GPS interference, or outages",
        "fresh downstream_exposure links to infrastructure or commodities",
      ]
    when "infrastructure_disruption", "infrastructure_exposure", "natural_hazard", "infrastructure_asset"
      [
        "new local_corroboration edges from cameras or other ground observations",
        "fresh outage, fire, NOTAM, or transport evidence near exposed assets",
        "new downstream_exposure links from nearby corridors or theaters",
      ]
    when "market_exposure", "supply_chain_exposure"
      [
        "commodity_price evidence moving against recent baselines",
        "new chokepoint_exposure or flow_dependency relationships",
        "fresh reporting that connects market movement to a specific place, actor, or corridor",
      ]
    else
      [
        "new evidence links",
        "new active relationships",
        "changes in confidence, freshness, or relationship type mix",
      ]
    end.tap do |items|
      items << "relationship freshness for #{relation_types.join(", ")}" if relation_types.any?
    end
  end

  def affected_entities(relationships)
    relationships.map do |relationship|
      {
        relation_type: relationship[:relation_type],
        direction: relationship[:direction],
        confidence: relationship[:confidence],
        node: relationship[:node],
      }.compact
    end
  end

  def actionable_assessment?(assessment)
    Array(assessment[:observed]).any? ||
      Array(assessment[:reported]).any? ||
      Array(assessment[:relationships]).any? { |relationship| ACTIONABLE_RELATIONSHIP_TYPES.include?(relationship[:relation_type].to_s) }
  end

  def summary_for(node:, situation_type:, relationships:, observed:, reported:, inferred:)
    parts = []
    parts << "#{node[:name]} is assessed as #{situation_type.tr("_", " ")}"
    parts << "#{relationships.size} active graph relationship#{relationships.size == 1 ? "" : "s"}"
    parts << "#{reported.size} reporting item#{reported.size == 1 ? "" : "s"}" if reported.any?
    parts << "#{observed.size} observed signal#{observed.size == 1 ? "" : "s"}" if observed.any?
    parts << "#{inferred.size} inferred exposure#{inferred.size == 1 ? "" : "s"}" if inferred.any?
    parts.join("; ")
  end

  def confidence_for(relationships:, evidence:, missing_data:)
    values = relationships.map { |relationship| relationship[:confidence].to_f } +
      evidence.map { |item| item[:confidence].to_f }
    base = values.any? ? (values.sum / values.size) * 100.0 : 30.0
    base -= [missing_data.size * 4, 20].min
    [[base.round, 15].max, 95].min
  end

  def coverage_quality(node:, context:, relationships:, evidence:, observed:, reported:)
    score = 0
    score += 18 if relationships.any?
    score += [relationships.size * 4, 16].min
    score += 18 if evidence.any?
    score += 18 if reported.any?
    score += 18 if observed.any?
    score += 6 if node[:latitude].present? && node[:longitude].present?
    score += 6 if Array(context[:memberships]).any?
    [score, 100].min
  end

  def situation_type_for(node, relationships: [])
    relation_types = relationships.map { |relationship| relationship[:relation_type].to_s }
    return "infrastructure_disruption" if relation_types.include?("infrastructure_disruption")
    return "infrastructure_exposure" if relation_types.include?("infrastructure_exposure")

    if node[:node_type] == "event"
      return "conflict_report" if node[:event_family] == "conflict"
      return "infrastructure_disruption" if node[:event_family] == "infrastructure"
      return "natural_hazard" if %w[disaster weather].include?(node[:event_family].to_s)

      return "#{node[:event_family]}_event" if node[:event_family].present?
    end

    case node[:entity_type]
    when "theater"
      "theater_assessment"
    when "corridor"
      "corridor_exposure"
    when "commodity"
      "market_exposure"
    when "country", "sector", "input"
      "supply_chain_exposure"
    when "airport", "military_base", "port", "power_plant", "submarine_cable"
      "infrastructure_asset"
    when "asset"
      "operational_asset"
    else
      "ontology_context"
    end
  end

  def unique_evidence(items)
    items.uniq { |item| [item[:type], item[:id], item[:role], item[:label]] }
  end

  def unique_strings(items)
    items.compact_blank.uniq
  end
end
