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
    relationships = Array(context[:relationships])
    evidence = assessment_evidence(context, relationships)
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

  def assessment_evidence(context, relationships)
    direct_evidence = Array(context[:evidence])
    relationship_evidence = relationships.flat_map { |relationship| Array(relationship[:evidence]) }
    unique_evidence(direct_evidence + relationship_evidence)
  end
end
