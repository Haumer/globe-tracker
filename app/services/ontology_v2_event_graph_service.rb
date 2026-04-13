class OntologyV2EventGraphService
  DERIVED_BY = "ontology_v2_event_graph_v1".freeze
  OCCURRED_AT = "occurred_at".freeze
  DEFAULT_ENTITY_EVENT_RELATION = "involved_in_event".freeze

  ENTITY_EVENT_ROLE_RELATIONS = {
    "initiator" => "initiated_event",
    "actor" => "participated_in_event",
    "participant" => "participated_in_event",
    "host" => "hosted_event",
    "mediator" => "mediated_event",
    "reporter" => "reported_event",
  }.freeze

  EVENT_ENTITY_ROLE_RELATIONS = {
    "target" => "targeted_entity",
    "victim" => "affected_entity",
    "affected_party" => "affected_entity",
    "affected_asset" => "affected_asset",
  }.freeze

  ACTOR_ROLES = (ENTITY_EVENT_ROLE_RELATIONS.keys - %w[reporter]).freeze
  TARGET_OR_AFFECTED_ROLES = EVENT_ENTITY_ROLE_RELATIONS.keys.freeze
  EVENT_ENTITY_RELATIONS = (ENTITY_EVENT_ROLE_RELATIONS.values + EVENT_ENTITY_ROLE_RELATIONS.values + [DEFAULT_ENTITY_EVENT_RELATION]).uniq.freeze

  class << self
    def sync(now: Time.current)
      new(now: now).sync
    end

    def sync_batch(cursor: nil, batch_size: 500, now: Time.current)
      new(now: now).sync_batch(cursor: cursor, batch_size: batch_size)
    end

    def health_report(limit: 50)
      new.health_report(limit: limit)
    end
  end

  def initialize(now: Time.current)
    @now = now
  end

  def sync
    result = {
      events: 0,
      place_relationships: 0,
      entity_relationships: 0,
      relationship_evidences: 0,
    }

    ActiveRecord::Base.transaction do
      event_scope.includes(:place_entity, ontology_event_entities: :ontology_entity).find_each do |event|
        payload = sync_event(event)
        result[:events] += 1
        result[:place_relationships] += payload.fetch(:place_relationships)
        result[:entity_relationships] += payload.fetch(:entity_relationships)
        result[:relationship_evidences] += payload.fetch(:relationship_evidences)
      end

      result[:health] = health_report
    end

    result
  end

  def sync_batch(cursor: nil, batch_size: 500)
    limit = batch_size.to_i.clamp(1, 5_000)
    events = event_scope
      .where(cursor.present? ? ["ontology_events.id > ?", cursor.to_i] : nil)
      .order(:id)
      .limit(limit)
      .includes(:place_entity, :ontology_evidence_links, ontology_event_entities: :ontology_entity)
      .to_a
    result = {
      cursor: cursor,
      next_cursor: events.size < limit ? nil : events.last&.id,
      records_fetched: events.size,
      records_stored: 0,
      events: 0,
      place_relationships: 0,
      entity_relationships: 0,
      relationship_evidences: 0,
      complete: events.size < limit,
    }

    ActiveRecord::Base.transaction do
      events.each do |event|
        payload = sync_event(event)
        result[:records_stored] += payload.fetch(:place_relationships) + payload.fetch(:entity_relationships)
        result[:events] += 1
        result[:place_relationships] += payload.fetch(:place_relationships)
        result[:entity_relationships] += payload.fetch(:entity_relationships)
        result[:relationship_evidences] += payload.fetch(:relationship_evidences)
      end
    end

    result
  end

  def health_report(limit: 50)
    events = event_scope.includes(:place_entity, :ontology_evidence_links, :ontology_event_entities).to_a
    relationships = relationship_scope

    {
      events: events.size,
      event_graph_relationships: relationships.count,
      event_place_relationships: relationships.where(relation_type: OCCURRED_AT).count,
      event_entity_relationships: relationships.where(relation_type: EVENT_ENTITY_RELATIONS).count,
      events_missing_evidence: event_issues(events.select { |event| event.ontology_evidence_links.empty? }, limit: limit),
      events_missing_actor: event_issues(events.reject { |event| event_has_role?(event, ACTOR_ROLES) }, limit: limit),
      events_missing_location_or_target: event_issues(
        events.reject { |event| event.place_entity.present? || event_has_role?(event, TARGET_OR_AFFECTED_ROLES) },
        limit: limit
      ),
      events_missing_time: event_issues(events.select { |event| event_time_missing?(event) }, limit: limit),
    }
  end

  private

  attr_reader :now

  def sync_event(event)
    desired_relationships = []
    counts = {
      place_relationships: 0,
      entity_relationships: 0,
      relationship_evidences: 0,
    }

    if event.place_entity.present?
      relationship = upsert_relationship(
        source_node: event,
        target_node: event.place_entity,
        relation_type: OCCURRED_AT,
        confidence: event.geo_confidence.presence || event.confidence,
        explanation: "#{event_label(event)} occurred at #{event.place_entity.canonical_name}.",
        metadata: event_metadata(event).merge(
          "geo_precision" => event.geo_precision,
          "geo_confidence" => event.geo_confidence
        )
      )
      desired_relationships << relationship_key(relationship)
      counts[:place_relationships] += 1
      counts[:relationship_evidences] += sync_relationship_evidences(relationship, event)
    end

    event.ontology_event_entities.each do |membership|
      entity = membership.ontology_entity
      next if entity.blank?

      payload = relationship_payload_for_membership(event, membership, entity)
      relationship = upsert_relationship(**payload)
      desired_relationships << relationship_key(relationship)
      counts[:entity_relationships] += 1
      counts[:relationship_evidences] += sync_relationship_evidences(relationship, event)
    end

    delete_stale_event_relationships(event, keep_keys: desired_relationships)
    counts
  end

  def relationship_payload_for_membership(event, membership, entity)
    normalized_role = membership.role.to_s
    relation_type = EVENT_ENTITY_ROLE_RELATIONS[normalized_role]

    if relation_type.present?
      return {
        source_node: event,
        target_node: entity,
        relation_type: relation_type,
        confidence: membership.confidence,
        explanation: "#{event_label(event)} has #{entity.canonical_name} as #{normalized_role.tr('_', ' ')}.",
        metadata: event_metadata(event).merge("role" => normalized_role),
      }
    end

    relation_type = ENTITY_EVENT_ROLE_RELATIONS.fetch(normalized_role, DEFAULT_ENTITY_EVENT_RELATION)
    {
      source_node: entity,
      target_node: event,
      relation_type: relation_type,
      confidence: membership.confidence,
      explanation: "#{entity.canonical_name} is #{normalized_role.tr('_', ' ')} in #{event_label(event)}.",
      metadata: event_metadata(event).merge("role" => normalized_role),
    }
  end

  def upsert_relationship(source_node:, target_node:, relation_type:, confidence:, explanation:, metadata:)
    OntologySyncSupport.upsert_relationship(
      source_node: source_node,
      target_node: target_node,
      relation_type: relation_type,
      confidence: confidence || 0.0,
      derived_by: DERIVED_BY,
      explanation: explanation,
      metadata: metadata.merge("synced_at" => now.iso8601)
    )
  end

  def sync_relationship_evidences(relationship, event)
    existing = relationship.ontology_relationship_evidences.index_by do |link|
      [link.evidence_type, link.evidence_id, link.evidence_role]
    end
    desired = {}

    event.ontology_evidence_links.each do |evidence_link|
      next if evidence_link.evidence.blank?

      evidence_role = "event_#{evidence_link.evidence_role}"
      key = [evidence_link.evidence_type, evidence_link.evidence_id, evidence_role]
      desired[key] = true
      OntologySyncSupport.upsert_relationship_evidence(
        relationship,
        evidence_link.evidence,
        evidence_role: evidence_role,
        confidence: evidence_link.confidence,
        metadata: {
          "ontology_event_id" => event.id,
          "event_canonical_key" => event.canonical_key,
          "event_evidence_role" => evidence_link.evidence_role,
        }
      )
    end

    stale_ids = existing.reject { |key, _link| desired[key] }.values.map(&:id)
    OntologyRelationshipEvidence.where(id: stale_ids).delete_all if stale_ids.any?
    desired.size
  end

  def delete_stale_event_relationships(event, keep_keys:)
    stale_ids = event_relationship_scope(event).reject do |relationship|
      keep_keys.include?(relationship_key(relationship))
    end.map(&:id)
    return if stale_ids.empty?

    OntologyRelationshipEvidence.where(ontology_relationship_id: stale_ids).delete_all
    OntologyRelationship.where(id: stale_ids).delete_all
  end

  def relationship_key(relationship)
    [
      relationship.source_node_type,
      relationship.source_node_id,
      relationship.target_node_type,
      relationship.target_node_id,
      relationship.relation_type,
    ]
  end

  def event_relationship_scope(event)
    OntologyRelationship
      .where(derived_by: DERIVED_BY)
      .where(
        "(source_node_type = ? AND source_node_id = ?) OR (target_node_type = ? AND target_node_id = ?)",
        event.class.name,
        event.id,
        event.class.name,
        event.id
      )
  end

  def relationship_scope
    OntologyRelationship.where(derived_by: DERIVED_BY)
  end

  def event_has_role?(event, roles)
    event.ontology_event_entities.any? { |membership| roles.include?(membership.role.to_s) }
  end

  def event_time_missing?(event)
    event.started_at.blank? && event.first_seen_at.blank? && event.last_seen_at.blank?
  end

  def event_issues(events, limit:)
    events.first(limit).map do |event|
      {
        id: event.id,
        canonical_key: event.canonical_key,
        event_type: event.event_type,
        event_family: event.event_family,
      }
    end
  end

  def event_metadata(event)
    {
      "ontology_event_id" => event.id,
      "event_canonical_key" => event.canonical_key,
      "event_family" => event.event_family,
      "event_type" => event.event_type,
      "verification_status" => event.verification_status,
      "status" => event.status,
    }.compact
  end

  def event_label(event)
    event.metadata["canonical_title"].presence || event.canonical_key
  end

  def event_scope
    OntologyEvent.all
  end
end
