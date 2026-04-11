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
  OBSERVED_RELATIONSHIP_TYPES = %w[impacted_infrastructure operational_activity local_corroboration].freeze
  ACTIONABLE_RELATIONSHIP_TYPES = %w[
    affected_entity
    exposed_infrastructure
    impacted_infrastructure
    infrastructure_disruption
    infrastructure_exposure
    initiated_event
    involved_in_event
    local_corroboration
    occurred_at
    operational_activity
    participated_in_event
    targeted_entity
    theater_pressure
  ].freeze
  INFERRED_RELATIONSHIP_TYPES = %w[
    affected_asset
    affected_entity
    chokepoint_exposure
    downstream_exposure
    economic_profile
    exposed_infrastructure
    flow_dependency
    hosted_event
    impacted_infrastructure
    infrastructure_disruption
    infrastructure_exposure
    initiated_event
    import_dependency
    involved_in_event
    lands_in_country
    located_in_country
    occurred_at
    participated_in_event
    place_resolves_to_country
    production_dependency
    represents_country
    targeted_entity
    theater_pressure
  ].freeze
  EVENT_LED_RELATIONSHIP_TYPES = %w[
    affected_asset
    affected_entity
    hosted_event
    impacted_infrastructure
    initiated_event
    involved_in_event
    participated_in_event
    targeted_entity
  ].freeze
  STATIC_CONTEXT_RELATIONSHIP_TYPES = %w[
    economic_profile
    import_dependency
    lands_in_country
    located_in_country
    place_resolves_to_country
    production_dependency
    represents_country
  ].freeze
  COUNTRY_EVENT_FAMILY_PRIORITY = {
    "conflict" => 0,
    "security" => 1,
    "diplomacy" => 2,
    "infrastructure" => 3,
    "cyber" => 4,
    "transport" => 5,
    "disaster" => 5,
    "economy" => 6,
    "humanitarian" => 9,
    "politics" => 9,
    "justice" => 9,
  }.freeze

  include RequestMethods
  include ContentMethods
  include ScoringMethods

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
    assessments = []

    recent_requests(limit: limit).each do |request|
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

  def build_assessment(context:, request_kind:, request_id:)
    node = context.fetch(:node)
    relationships = assessment_relationships(context: context, node: node)
    evidence = assessment_evidence(context, relationships)
    observed = observed_items(relationships: relationships, evidence: evidence)
    reported = reported_items(evidence)
    inferred = inferred_items(relationships, node: node)
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

  def assessment_evidence(context, relationships)
    direct_evidence = Array(context[:evidence])
    relationship_evidence = relationships.flat_map { |relationship| Array(relationship[:evidence]) }
    unique_evidence(direct_evidence + relationship_evidence)
  end

  def assessment_relationships(context:, node:)
    relationships = Array(context[:relationships])
    relationships += country_event_relationships(node) if country_node?(node)

    relationships
      .uniq { |relationship| relationship_identity(relationship) }
      .sort_by { |relationship| assessment_relationship_sort_key(node, relationship) }
      .first(MAX_ITEMS * 4)
  end

  def country_event_relationships(node)
    country = OntologyEntity.find_by(id: node[:id], entity_type: "country")
    return [] if country.blank?

    anchors = ([country] + state_actors_for_country(country)).uniq(&:id)
    anchor_ids = anchors.map(&:id)
    return [] if anchor_ids.empty?

    relationships = OntologyRelationship.active
      .includes(:source_node, :target_node, :ontology_relationship_evidences)
      .where(derived_by: OntologyV2EventGraphService::DERIVED_BY, relation_type: EVENT_LED_RELATIONSHIP_TYPES)
      .where(
        "(source_node_type = 'OntologyEntity' AND source_node_id IN (:ids) AND target_node_type = 'OntologyEvent') OR " \
          "(target_node_type = 'OntologyEntity' AND target_node_id IN (:ids) AND source_node_type = 'OntologyEvent')",
        ids: anchor_ids
      )
      .to_a

    relationships
      .select { |relationship| country_event_relationship_relevant?(relationship, country: country, anchors: anchors) }
      .sort_by { |relationship| [-event_counterparty_time(relationship).to_i, -relationship.confidence.to_f] }
      .first(MAX_ITEMS * 3)
      .map { |relationship| serialize_country_event_relationship(relationship, country: country, anchors: anchors) }
  end

  def serialize_country_event_relationship(relationship, country:, anchors:)
    source_anchor = relationship.source_node_type == "OntologyEntity" ? anchors.find { |node| node.id == relationship.source_node_id } : nil
    target_anchor = relationship.target_node_type == "OntologyEntity" ? anchors.find { |node| node.id == relationship.target_node_id } : nil
    anchor = source_anchor || target_anchor || country
    direction = source_anchor.present? ? "outgoing" : "incoming"
    payload = NodeContextService.send(:serialize_relationship, relationship, direction: direction)

    if anchor != country
      payload[:via_node] = NodeContextService.send(:serialize_node, anchor)
      payload[:context_basis] = "country_state_actor_event_graph"
    end

    payload
  end

  def state_actors_for_country(country)
    actors = OntologyRelationship
      .includes(:source_node)
      .where(
        target_node: country,
        relation_type: OntologyV2IdentityService::REPRESENTS_COUNTRY,
        derived_by: OntologyV2IdentityService::DERIVED_BY
      )
      .filter_map(&:source_node)

    country_codes = [
      country.country_code,
      country.metadata["country_code_alpha3"],
      country.canonical_key.to_s.split(":").last,
    ].compact_blank.map { |code| code.to_s.downcase }

    actor_keys = country_codes.map { |code| "actor:state:#{code}" }
    actors + OntologyEntity.where(entity_type: "actor", canonical_key: actor_keys).to_a
  end

  def event_counterparty_time(relationship)
    event = relationship.source_node.is_a?(OntologyEvent) ? relationship.source_node : relationship.target_node
    event.last_seen_at || event.first_seen_at || event.started_at || event.updated_at
  end

  def assessment_relationship_sort_key(node, relationship)
    [
      static_context_relationship?(node, relationship) ? 1 : 0,
      country_event_family_priority(node, relationship),
      NodeContextService::RELATIONSHIP_PRIORITY.fetch(relationship.fetch(:relation_type).to_s, 100),
      -relationship.fetch(:confidence).to_f,
      relationship.dig(:node, :name).to_s,
    ]
  end

  def relationship_identity(relationship)
    node = relationship[:node] || {}
    via = relationship[:via_node] || {}
    [
      relationship[:direction],
      relationship[:relation_type],
      node[:node_type],
      node[:id],
      via[:node_type],
      via[:id],
    ]
  end

  def country_node?(node)
    node[:node_type] == "entity" && node[:entity_type] == "country"
  end

  def static_context_relationship?(node, relationship)
    country_node?(node) && STATIC_CONTEXT_RELATIONSHIP_TYPES.include?(relationship[:relation_type].to_s)
  end

  def country_event_family_priority(node, relationship)
    return 0 unless country_node?(node)
    return 100 unless relationship.dig(:node, :node_type) == "event"

    COUNTRY_EVENT_FAMILY_PRIORITY.fetch(relationship.dig(:node, :event_family).to_s, 50)
  end

  def country_event_relationship_relevant?(relationship, country:, anchors:)
    event = relationship.source_node.is_a?(OntologyEvent) ? relationship.source_node : relationship.target_node
    anchor = relationship.source_node.is_a?(OntologyEntity) ? relationship.source_node : relationship.target_node
    return false unless event.is_a?(OntologyEvent)
    return true if anchor == country
    return false if event.metadata["content_scope"].present? && event.metadata["content_scope"] != "core"

    event_text = [event.metadata["canonical_title"], event.metadata["location_name"]].compact.join(" ").downcase
    relevant_names = ([country.canonical_name.to_s.split(",").first] + anchors.map(&:canonical_name))
      .compact_blank
      .map { |name| name.to_s.downcase }
      .uniq
    relevant_names.any? { |name| event_text.include?(name) }
  end
end
