class OntologyV2InfrastructureImpactService
  DERIVED_BY = "ontology_v2_infrastructure_impact_v1".freeze
  IMPACTED_INFRASTRUCTURE = "impacted_infrastructure".freeze
  EXPOSED_INFRASTRUCTURE = "exposed_infrastructure".freeze
  ASSET_ENTITY_TYPES = OntologyV2AssetGraphService::ASSET_ENTITY_TYPES.values.freeze
  DIRECT_IMPACT_ROLES = %w[target victim affected_party affected_asset].freeze
  COUNTRY_EXPOSURE_LIMIT = 12
  NEARBY_ASSET_LIMIT = 16
  NON_INFRASTRUCTURE_EVENT_TYPES = %w[
    agreement
    aid_delivery
    arrest_detention
    ceasefire
    diplomatic_contact
    election
    negotiation
    official_visit
    protest
    sanction_action
    summit
    trade_measure
  ].freeze
  NON_INFRASTRUCTURE_EVENT_FAMILIES = %w[
    diplomacy
    economy
    humanitarian
    justice
    politics
  ].freeze
  NEARBY_IMPACT_EVENT_PATTERN = /\b(airstrike|attack|crash|earthquake|explosion|fire|flood|geoconfirmed strike|missile attack|storm|strike|wildfire)\b/i
  NEARBY_EXPOSURE_EVENT_PATTERN = /\b(airstrike|attack|blackout|crash|cyberattack|earthquake|explosion|fire|flood|geoconfirmed strike|missile attack|outage|storm|strike|wildfire)\b/i
  MEDIA_LOCATION_PATTERN = /\b(associated press|bbc|cnn|dw|euronews|france 24|guardian|journal|newshour|npr|nyt|pbs|polsat|post|repubblica|reuters|times|zeit)\b/i
  SHORT_NEWS_SOURCE_NAMES = %w[ap afp bbc cnn dw npr pbs].freeze

  class << self
    def sync(now: Time.current)
      new(now: now).sync
    end

    def sync_batch(cursor: nil, batch_size: 500, now: Time.current)
      new(now: now).sync_batch(cursor: cursor, batch_size: batch_size)
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
      event_scope.includes(:place_entity, :primary_story_cluster, :ontology_evidence_links, ontology_event_entities: :ontology_entity).find_each do |event|
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

  def sync_batch(cursor: nil, batch_size: 500)
    limit = batch_size.to_i.clamp(1, 5_000)
    events = event_scope
      .where(cursor.present? ? ["ontology_events.id > ?", cursor.to_i] : nil)
      .order(:id)
      .limit(limit)
      .includes(:place_entity, :primary_story_cluster, :ontology_evidence_links, ontology_event_entities: :ontology_entity)
      .to_a
    result = {
      cursor: cursor,
      next_cursor: events.size < limit ? nil : events.last&.id,
      records_fetched: events.size,
      records_stored: 0,
      events: 0,
      impact_relationships: 0,
      relationship_evidences: 0,
      complete: events.size < limit,
    }

    ActiveRecord::Base.transaction do
      events.each do |event|
        payload = sync_event(event)
        result[:records_stored] += payload.fetch(:relationships)
        next if payload.fetch(:relationships).zero?

        result[:events] += 1
        result[:impact_relationships] += payload.fetch(:relationships)
        result[:relationship_evidences] += payload.fetch(:relationship_evidences)
      end
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
    candidates += nearby_asset_candidates(event) if nearby_infrastructure_context?(event)
    candidates += country_asset_candidates(event) if country_infrastructure_context?(event)
    strongest_candidate_per_asset(candidates)
  end

  def direct_asset_candidates(event)
    event.ontology_event_entities.filter_map do |membership|
      entity = membership.ontology_entity
      next unless asset_entity?(entity)
      next unless DIRECT_IMPACT_ROLES.include?(membership.role.to_s)
      next unless relevant_for_infrastructure?(event)

      relation_type = direct_impact_event?(event) ? IMPACTED_INFRASTRUCTURE : EXPOSED_INFRASTRUCTURE
      {
        entity: entity,
        relation_type: relation_type,
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

      relation_type, basis = nearby_asset_relationship_assessment(event, asset, distance)
      {
        entity: asset,
        relation_type: relation_type,
        confidence: proximity_confidence(event, distance, radius_km, relation_type),
        basis: basis,
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
      .includes(:place_entity, :primary_story_cluster, :ontology_event_entities)
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
    return false if non_infrastructure_context_event?(event)

    direct_impact_event?(event) ||
      nearby_exposure_event?(event) ||
      event.event_family.to_s.in?(%w[infrastructure transport disaster cyber])
  end

  def nearby_infrastructure_context?(event)
    return false if publisher_labeled_coordinates?(event) && !event.event_family.to_s.in?(%w[disaster transport])

    relevant_for_infrastructure?(event) && nearby_exposure_event?(event) && trustworthy_point_location?(event)
  end

  def country_infrastructure_context?(event)
    relevant_for_infrastructure?(event) && nearby_exposure_event?(event)
  end

  def direct_impact_event?(event)
    nearby_impact_event?(event) || event_type_text(event).match?(/\b(outage|cyberattack)\b/i)
  end

  def nearby_impact_event?(event)
    return false if non_infrastructure_context_event?(event)

    event_type_text(event).match?(NEARBY_IMPACT_EVENT_PATTERN)
  end

  def nearby_impact_allowed?(event)
    return false if publisher_labeled_coordinates?(event)

    nearby_impact_event?(event)
  end

  def nearby_asset_relationship_assessment(event, asset, distance)
    if nearby_impact_allowed?(event) &&
        distance <= direct_impact_radius_km(asset.entity_type) &&
        asset_directly_referenced?(event_reference_text(event), asset)
      return [IMPACTED_INFRASTRUCTURE, "direct_asset_reference"]
    end

    [EXPOSED_INFRASTRUCTURE, "event_proximity_exposure"]
  end

  def nearby_exposure_event?(event)
    return false if non_infrastructure_context_event?(event)

    event_type_text(event).match?(NEARBY_EXPOSURE_EVENT_PATTERN) ||
      event.event_family.to_s.in?(%w[infrastructure transport disaster cyber])
  end

  def non_infrastructure_context_event?(event)
    return true if NON_INFRASTRUCTURE_EVENT_TYPES.include?(event.event_type.to_s)
    return false if event_type_text(event).match?(NEARBY_EXPOSURE_EVENT_PATTERN)

    NON_INFRASTRUCTURE_EVENT_FAMILIES.include?(event.event_family.to_s)
  end

  def event_type_text(event)
    event.event_type.to_s.tr("_-", " ")
  end

  def trustworthy_point_location?(event)
    lat, lng = event_coordinates(event)
    return false if lat.blank? || lng.blank?

    coordinate_payload = event_coordinate_payload(event)
    return false unless coordinate_payload[:geo_precision].to_s == "point"
    return false if coordinate_payload[:geo_confidence].to_f < 0.45
    return false if coordinate_payload[:source] == "place_entity" && publisher_location_name?(event)

    true
  end

  def publisher_location_name?(event)
    location_names = [
      event.metadata["location_name"],
      event.primary_story_cluster&.location_name,
      event.place_entity&.canonical_name,
    ].compact_blank

    location_names.any? { |value| known_news_source_name?(value) }
  end

  def publisher_labeled_coordinates?(event)
    event_coordinate_payload(event)[:source] == "primary_story_cluster" && publisher_location_name?(event)
  end

  def known_news_source_name?(value)
    normalized = normalize_source_name(value)
    return false if normalized.blank?

    known_news_source_names[normalized] ||
      known_news_source_names[normalized.delete(" ")] ||
      known_news_source_name_fragments.any? { |source_name| normalized.include?(source_name) } ||
      (normalized.split & SHORT_NEWS_SOURCE_NAMES).any? ||
      normalized.match?(MEDIA_LOCATION_PATTERN)
  end

  def known_news_source_names
    @known_news_source_names ||= NewsSource.pluck(:name).each_with_object({}) do |name, memo|
      normalized = normalize_source_name(name)
      next if normalized.blank?

      memo[normalized] = true
      memo[normalized.delete(" ")] = true
    end
  end

  def known_news_source_name_fragments
    @known_news_source_name_fragments ||= known_news_source_names.keys.select { |name| name.length >= 4 }
  end

  def normalize_source_name(value)
    value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squish.delete_prefix("the ")
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
      if candidate.fetch(:basis) == "direct_asset_reference"
        "#{event_label(event)} directly references #{candidate.fetch(:entity).canonical_name}, indicating likely infrastructure impact."
      else
        "#{event_label(event)} identifies #{candidate.fetch(:entity).canonical_name} as #{candidate.fetch(:role, 'affected infrastructure').to_s.tr('_', ' ')}."
      end
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
    payload = event_coordinate_payload(event)
    [payload[:latitude], payload[:longitude]]
  end

  def event_coordinate_payload(event)
    cluster = event.primary_story_cluster
    if cluster&.latitude.present? && cluster&.longitude.present?
      return {
        latitude: cluster.latitude,
        longitude: cluster.longitude,
        geo_precision: cluster.geo_precision,
        geo_confidence: cluster.geo_confidence,
        source: "primary_story_cluster",
      }
    end

    if event.metadata["latitude"].present? && event.metadata["longitude"].present?
      return {
        latitude: event.metadata["latitude"],
        longitude: event.metadata["longitude"],
        geo_precision: event.geo_precision,
        geo_confidence: event.geo_confidence,
        source: "event_metadata",
      }
    end

    place_metadata = event.place_entity&.metadata || {}
    {
      latitude: place_metadata["latitude"],
      longitude: place_metadata["longitude"],
      geo_precision: place_metadata["geo_precision"] || event.geo_precision,
      geo_confidence: event.geo_confidence,
      source: "place_entity",
    }
  end

  def entity_coordinates(entity)
    [entity.metadata["latitude"], entity.metadata["longitude"]]
  end

  def event_reference_text(event)
    [
      event.metadata["canonical_title"],
      event.metadata["location_name"],
      event.primary_story_cluster&.canonical_title,
      event.primary_story_cluster&.location_name,
      event.place_entity&.canonical_name,
    ].compact_blank.join(" ")
  end

  def asset_directly_referenced?(text, asset)
    normalized_text = normalize_asset_reference_text(text)
    return false if normalized_text.blank?

    asset_reference_terms(asset).any? do |term|
      normalized_term = normalize_asset_reference_text(term)
      normalized_term.length >= 5 && normalized_text.include?(normalized_term)
    end
  end

  def asset_reference_terms(asset)
    [
      asset.canonical_name,
      asset.canonical_key,
      *asset.ontology_entity_aliases.pluck(:name),
    ].compact_blank.uniq
  end

  def normalize_asset_reference_text(value)
    value.to_s.downcase.gsub(/[^\p{Alnum}]+/, " ").squish
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
