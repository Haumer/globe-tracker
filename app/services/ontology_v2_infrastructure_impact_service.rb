class OntologyV2InfrastructureImpactService
  DERIVED_BY = "ontology_v2_infrastructure_impact_v1".freeze
  IMPACTED_INFRASTRUCTURE = "impacted_infrastructure".freeze
  EXPOSED_INFRASTRUCTURE = "exposed_infrastructure".freeze
  ASSET_ENTITY_TYPES = OntologyV2AssetGraphService::ASSET_ENTITY_TYPES.values.freeze
  DIRECT_IMPACT_ROLES = %w[target victim affected_party affected_asset].freeze
  COUNTRY_EXPOSURE_LIMIT = 12
  NEARBY_ASSET_LIMIT = 16

  class << self
    def sync(now: Time.current)
      new(now: now).sync
    end

    def health_report
      new.health_report
    end
  end

  def initialize(now: Time.current)
    @now = now
  end

  def sync
    result = {
      events: 0,
      impact_relationships: 0,
      relationship_evidences: 0,
    }

    ActiveRecord::Base.transaction do
      event_scope.includes(:place_entity, :ontology_evidence_links, ontology_event_entities: :ontology_entity).find_each do |event|
        payload = sync_event(event)
        next if payload.fetch(:relationships).zero?

        result[:events] += 1
        result[:impact_relationships] += payload.fetch(:relationships)
        result[:relationship_evidences] += payload.fetch(:relationship_evidences)
      end

      result[:health] = health_report
    end

    result
  end

  def health_report
    relationships = relationship_scope

    {
      impact_relationships: relationships.count,
      impacted_infrastructure: relationships.where(relation_type: IMPACTED_INFRASTRUCTURE).count,
      exposed_infrastructure: relationships.where(relation_type: EXPOSED_INFRASTRUCTURE).count,
      recent_relevant_events_without_infrastructure_context: recent_relevant_events_without_infrastructure_context,
    }
  end

  private

  attr_reader :now

  def sync_event(event)
    candidates = infrastructure_candidates_for(event)
    desired_relationships = []
    counts = {
      relationships: 0,
      relationship_evidences: 0,
    }

    candidates.each do |candidate|
      relationship = OntologySyncSupport.upsert_relationship(
        source_node: event,
        target_node: candidate.fetch(:entity),
        relation_type: candidate.fetch(:relation_type),
        confidence: candidate.fetch(:confidence),
        derived_by: DERIVED_BY,
        explanation: impact_explanation(event, candidate),
        metadata: impact_metadata(event, candidate)
      )

      desired_relationships << relationship_key(relationship)
      counts[:relationships] += 1
      counts[:relationship_evidences] += sync_relationship_evidences(relationship, event)
    end

    delete_stale_event_relationships(event, keep_keys: desired_relationships)
    counts
  end

  def infrastructure_candidates_for(event)
    candidates = direct_asset_candidates(event)
    candidates += nearby_asset_candidates(event) if relevant_for_infrastructure?(event)
    candidates += country_asset_candidates(event) if relevant_for_infrastructure?(event)
    strongest_candidate_per_asset(candidates)
  end

  def direct_asset_candidates(event)
    event.ontology_event_entities.filter_map do |membership|
      entity = membership.ontology_entity
      next unless asset_entity?(entity)
      next unless DIRECT_IMPACT_ROLES.include?(membership.role.to_s)

      {
        entity: entity,
        relation_type: IMPACTED_INFRASTRUCTURE,
        confidence: [[membership.confidence.to_f, event.confidence.to_f].max, 0.95].min,
        basis: "direct_event_role",
        role: membership.role.to_s,
      }
    end
  end

  def nearby_asset_candidates(event)
    lat, lng = event_coordinates(event)
    return [] if lat.blank? || lng.blank?

    radius_km = event_radius_km(event)
    lat = lat.to_f
    lng = lng.to_f
    nearby_asset_payloads(lat: lat, lng: lng, radius_km: radius_km).map do |payload|
      asset = payload.fetch(:entity)
      distance = haversine_km(lat, lng, payload.fetch(:latitude), payload.fetch(:longitude))
      next if distance > radius_km

      relation_type = disruptive_event?(event) && distance <= direct_impact_radius_km(asset.entity_type) ? IMPACTED_INFRASTRUCTURE : EXPOSED_INFRASTRUCTURE
      {
        entity: asset,
        relation_type: relation_type,
        confidence: proximity_confidence(event, distance, radius_km, relation_type),
        basis: "event_proximity",
        distance_km: distance,
        radius_km: radius_km,
      }
    end.compact
      .sort_by { |candidate| [candidate.fetch(:relation_type) == IMPACTED_INFRASTRUCTURE ? 0 : 1, candidate.fetch(:distance_km), candidate.fetch(:entity).canonical_name] }
      .first(NEARBY_ASSET_LIMIT)
  end

  def country_asset_candidates(event)
    countries = event_countries(event)
    return [] if countries.empty?

    asset_country_relationships(countries).first(COUNTRY_EXPOSURE_LIMIT).map do |relationship|
      {
        entity: relationship.source_node,
        relation_type: EXPOSED_INFRASTRUCTURE,
        confidence: country_exposure_confidence(event, relationship),
        basis: relationship.relation_type,
        country_canonical_key: relationship.target_node.canonical_key,
      }
    end
  end

  def strongest_candidate_per_asset(candidates)
    candidates.group_by { |candidate| candidate.fetch(:entity).id }.values.map do |group|
      group.max_by do |candidate|
        [
          candidate.fetch(:relation_type) == IMPACTED_INFRASTRUCTURE ? 1 : 0,
          candidate.fetch(:confidence).to_f,
          -candidate.fetch(:distance_km, 999_999).to_f,
        ]
      end
    end.sort_by { |candidate| [-candidate.fetch(:confidence).to_f, candidate.fetch(:entity).canonical_name] }
  end

  def asset_country_relationships(countries)
    OntologyRelationship
      .includes(:source_node, :target_node)
      .where(
        target_node: countries,
        relation_type: [
          OntologyV2AssetGraphService::LOCATED_IN_COUNTRY,
          OntologyV2AssetGraphService::LANDS_IN_COUNTRY,
        ],
        derived_by: OntologyV2AssetGraphService::DERIVED_BY
      )
      .to_a
      .select { |relationship| asset_entity?(relationship.source_node) }
      .sort_by { |relationship| [asset_country_priority(relationship.source_node), relationship.source_node.canonical_name] }
  end

  def event_countries(event)
    countries = event.ontology_event_entities.filter_map do |membership|
      entity = membership.ontology_entity
      next unless DIRECT_IMPACT_ROLES.include?(membership.role.to_s)
      next unless entity&.entity_type == "country"

      entity
    end

    if event.place_entity.present?
      countries << event.place_entity if event.place_entity.entity_type == "country"
      countries += OntologyRelationship.where(
        source_node: event.place_entity,
        relation_type: OntologyV2IdentityService::PLACE_RESOLVES_TO_COUNTRY,
        derived_by: OntologyV2IdentityService::DERIVED_BY
      ).filter_map(&:target_node)
    end

    countries.uniq(&:id)
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
    stale_ids = OntologyRelationship
      .where(source_node: event, relation_type: [IMPACTED_INFRASTRUCTURE, EXPOSED_INFRASTRUCTURE], derived_by: DERIVED_BY)
      .to_a
      .reject { |relationship| keep_keys.include?(relationship_key(relationship)) }
      .map(&:id)
    return if stale_ids.empty?

    OntologyRelationshipEvidence.where(ontology_relationship_id: stale_ids).delete_all
    OntologyRelationship.where(id: stale_ids).delete_all
  end

  def recent_relevant_events_without_infrastructure_context
    linked_event_ids = relationship_scope.where(source_node_type: "OntologyEvent").pluck(:source_node_id).index_with(true)
    event_scope
      .includes(:place_entity, :ontology_event_entities)
      .select { |event| relevant_for_infrastructure?(event) && !linked_event_ids[event.id] }
      .first(50)
      .map do |event|
        {
          id: event.id,
          canonical_key: event.canonical_key,
          event_family: event.event_family,
          event_type: event.event_type,
          has_coordinates: event_coordinates(event).all?(&:present?),
          country_keys: event_countries(event).map(&:canonical_key),
        }
      end
  end

  def event_scope
    OntologyEvent.where("COALESCE(last_seen_at, first_seen_at, started_at, updated_at) >= ?", now - 14.days)
  end

  def relationship_scope
    OntologyRelationship.where(derived_by: DERIVED_BY)
  end

  def asset_scope
    OntologyEntity.where(entity_type: ASSET_ENTITY_TYPES)
  end

  def nearby_asset_payloads(lat:, lng:, radius_km:)
    lat_delta = radius_km.to_f / 111.0
    lng_delta = radius_km.to_f / [111.0 * Math.cos(lat * Math::PI / 180.0).abs, 1.0].max

    asset_coordinate_payloads.select do |payload|
      (payload.fetch(:latitude) - lat).abs <= lat_delta &&
        (payload.fetch(:longitude) - lng).abs <= lng_delta
    end
  end

  def asset_coordinate_payloads
    @asset_coordinate_payloads ||= asset_scope.filter_map do |asset|
      lat, lng = entity_coordinates(asset)
      next if lat.blank? || lng.blank?

      {
        entity: asset,
        latitude: lat.to_f,
        longitude: lng.to_f,
      }
    end
  end

  def relevant_for_infrastructure?(event)
    return false if %w[diplomacy politics economy justice humanitarian].include?(event.event_family.to_s)

    event.event_family.to_s.in?(%w[conflict security infrastructure transport disaster cyber]) ||
      event.event_type.to_s.match?(/\b(strike|attack|explosion|outage|fire|flood|storm|earthquake|crash)\b/i)
  end

  def disruptive_event?(event)
    event_type_text = event.event_type.to_s.tr("_-", " ")
    title_text = event.metadata["canonical_title"].to_s
    event_type_text.match?(/\b(strike|attack|explosion|outage|fire|flood|storm|earthquake|crash)\b/i) ||
      title_text.match?(/\b(hit|strike|strikes|struck|attack|attacks|damag|destroy|burn|closed|outage|blackout|disrupt)\b/i)
  end

  def event_radius_km(event)
    return 160.0 if event.event_type.to_s == "earthquake"
    return 120.0 if event.event_type.to_s.match?(/\b(flood|storm)\b/i)
    return 70.0 if event.event_type.to_s.match?(/\b(outage|fire)\b/i)
    return 55.0 if event.event_family.to_s == "conflict"

    45.0
  end

  def direct_impact_radius_km(asset_type)
    {
      "airport" => 8.0,
      "military_base" => 10.0,
      "port" => 10.0,
      "power_plant" => 8.0,
      "submarine_cable" => 5.0,
    }.fetch(asset_type.to_s, 6.0)
  end

  def proximity_confidence(event, distance_km, radius_km, relation_type)
    base = event.confidence.to_f.positive? ? event.confidence.to_f : 0.55
    distance_factor = 1.0 - (distance_km.to_f / radius_km.to_f)
    confidence = base * 0.55 + distance_factor * 0.35
    confidence += 0.08 if relation_type == IMPACTED_INFRASTRUCTURE
    [[confidence, 0.35].max, 0.92].min.round(2)
  end

  def country_exposure_confidence(event, relationship)
    base = event.confidence.to_f.positive? ? event.confidence.to_f : 0.5
    confidence = base * 0.5 + relationship.confidence.to_f * 0.3 + 0.1
    [[confidence, 0.35].max, 0.78].min.round(2)
  end

  def asset_country_priority(entity)
    {
      "port" => 0,
      "submarine_cable" => 1,
      "power_plant" => 2,
      "airport" => 3,
      "military_base" => 4,
    }.fetch(entity.entity_type.to_s, 9)
  end

  def impact_explanation(event, candidate)
    if candidate.fetch(:relation_type) == IMPACTED_INFRASTRUCTURE
      "#{event_label(event)} directly impacts #{candidate.fetch(:entity).canonical_name}."
    elsif candidate[:distance_km].present?
      "#{event_label(event)} occurred #{candidate.fetch(:distance_km).round(1)}km from #{candidate.fetch(:entity).canonical_name}, exposing nearby infrastructure."
    else
      "#{event_label(event)} affects #{candidate[:country_canonical_key]}, exposing #{candidate.fetch(:entity).canonical_name}."
    end
  end

  def impact_metadata(event, candidate)
    {
      "ontology_event_id" => event.id,
      "event_canonical_key" => event.canonical_key,
      "event_family" => event.event_family,
      "event_type" => event.event_type,
      "asset_type" => candidate.fetch(:entity).entity_type,
      "basis" => candidate.fetch(:basis),
      "role" => candidate[:role],
      "distance_km" => candidate[:distance_km]&.round(1),
      "radius_km" => candidate[:radius_km]&.round(1),
      "country_canonical_key" => candidate[:country_canonical_key],
      "synced_at" => now.iso8601,
    }.compact
  end

  def event_coordinates(event)
    place_metadata = event.place_entity&.metadata || {}
    [
      place_metadata["latitude"] || event.metadata["latitude"],
      place_metadata["longitude"] || event.metadata["longitude"],
    ]
  end

  def entity_coordinates(entity)
    [entity.metadata["latitude"], entity.metadata["longitude"]]
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

  def asset_entity?(entity)
    entity.present? && ASSET_ENTITY_TYPES.include?(entity.entity_type)
  end

  def event_label(event)
    event.metadata["canonical_title"].presence || event.canonical_key
  end

  def haversine_km(lat1, lng1, lat2, lng2)
    radians_per_degree = Math::PI / 180.0
    dlat = (lat2 - lat1) * radians_per_degree
    dlng = (lng2 - lng1) * radians_per_degree
    a = Math.sin(dlat / 2)**2 +
      Math.cos(lat1 * radians_per_degree) *
      Math.cos(lat2 * radians_per_degree) *
      Math.sin(dlng / 2)**2
    6371.0 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
  end
end
