class OntologyRelationshipSyncService
  module InfrastructureDisruptionMethods
    private

    def sync_infrastructure_disruption_relationships(now:)
      recent_infrastructure_disruption_events(now: now).sum do |payload|
        event = sync_infrastructure_disruption_event(payload)
        sync_hazard_asset_relationships(event: event, payload: payload, now: now)
      end
    end

    def sync_infrastructure_disruption_event(payload)
      return payload.fetch(:ontology_event) if payload[:ontology_event].present?

      record = payload.fetch(:record)
      event = OntologyEvent.find_or_initialize_by(canonical_key: infrastructure_disruption_event_key(payload))
      event.place_entity = sync_hazard_place_entity(payload)
      event.event_family = payload.fetch(:event_family, "infrastructure")
      event.event_type = payload.fetch(:event_type, payload.fetch(:kind).to_s)
      event.status = "active"
      event.verification_status = "single_source"
      event.geo_precision = "point"
      event.confidence = payload.fetch(:confidence)
      event.source_reliability = 0.72
      event.geo_confidence = 0.86
      event.started_at ||= payload.fetch(:observed_at)
      event.first_seen_at ||= payload.fetch(:observed_at)
      event.last_seen_at = payload.fetch(:observed_at)
      event.metadata = infrastructure_event_metadata(payload)
      event.save!

      OntologySyncSupport.upsert_evidence_link(
        event,
        record,
        evidence_role: "hazard_observation",
        confidence: payload.fetch(:confidence),
        metadata: { "event_kind" => payload.fetch(:kind).to_s }
      )

      event
    end

    def sync_hazard_place_entity(payload)
      OntologySyncSupport.upsert_entity(
        canonical_key: "place:hazard:#{payload.fetch(:kind)}:#{record_stable_identifier(payload.fetch(:record))}",
        entity_type: "place",
        canonical_name: payload.fetch(:title),
        metadata: {
          "latitude" => payload.fetch(:latitude),
          "longitude" => payload.fetch(:longitude),
          "geo_precision" => "point",
          "event_kind" => payload.fetch(:kind).to_s,
        }
      ).tap do |entity|
        OntologySyncSupport.upsert_alias(entity, payload.fetch(:title), alias_type: "event_location")
      end
    end

    def sync_hazard_asset_relationships(event:, payload:, now:)
      desired_relationships = []
      candidates = infrastructure_disruption_asset_candidates(payload, now: now)

      relationship_count = candidates.count do |candidate|
        relation_type = infrastructure_relationship_type(payload, candidate)
        desired_relationships << [candidate.fetch(:entity).id, relation_type]

        relationship = upsert_infrastructure_relationship(
          event: event,
          payload: payload,
          candidate: candidate,
          relation_type: relation_type,
          now: now
        )
        sync_relationship_evidences(relationship, infrastructure_relationship_evidence_payloads(payload, candidate))
        true
      end

      prune_stale_infrastructure_relationships(event, desired_relationships)
      relationship_count
    end

    def upsert_infrastructure_relationship(event:, payload:, candidate:, relation_type:, now:)
      OntologySyncSupport.upsert_relationship(
        source_node: event,
        target_node: candidate.fetch(:entity),
        relation_type: relation_type,
        confidence: infrastructure_disruption_confidence(payload, candidate),
        fresh_until: [payload.fetch(:observed_at), now].compact.max + INFRASTRUCTURE_DISRUPTION_FRESHNESS,
        derived_by: RELATION_DERIVED_BY,
        explanation: infrastructure_disruption_explanation(payload, candidate),
        metadata: infrastructure_relationship_metadata(payload, candidate)
      )
    end

    def infrastructure_event_metadata(payload)
      {
        "canonical_title" => payload.fetch(:title),
        "event_kind" => payload.fetch(:kind).to_s,
        "event_type" => payload.fetch(:event_type, payload.fetch(:kind).to_s),
        "severity" => payload.fetch(:severity),
        "radius_km" => payload.fetch(:radius_km).round(1),
        "latitude" => payload.fetch(:latitude),
        "longitude" => payload.fetch(:longitude),
      }.compact
    end

    def infrastructure_relationship_metadata(payload, candidate)
      {
        "event_kind" => payload.fetch(:kind).to_s,
        "event_type" => payload.fetch(:event_type, payload.fetch(:kind).to_s),
        "severity" => payload.fetch(:severity),
        "asset_type" => candidate.fetch(:asset_type).to_s,
        "distance_km" => candidate.fetch(:distance_km).round(1),
        "radius_km" => payload.fetch(:radius_km).round(1),
        "observed_at" => payload.fetch(:observed_at)&.iso8601,
      }.compact
    end

    def infrastructure_relationship_evidence_payloads(payload, candidate)
      [
        {
          evidence: payload.fetch(:record),
          evidence_role: "hazard_observation",
          confidence: payload.fetch(:confidence),
          metadata: {
            "event_kind" => payload.fetch(:kind).to_s,
            "severity" => payload.fetch(:severity),
            "observed_at" => payload.fetch(:observed_at)&.iso8601,
          }.compact,
        },
        {
          evidence: candidate.fetch(:record),
          evidence_role: "exposed_asset",
          confidence: candidate.fetch(:confidence),
          metadata: {
            "asset_type" => candidate.fetch(:asset_type).to_s,
            "distance_km" => candidate.fetch(:distance_km).round(1),
          },
        },
      ] + Array(candidate[:supporting_evidence])
    end

    def prune_stale_infrastructure_relationships(event, desired_relationships)
      stale_ids = event.outgoing_ontology_relationships
        .where(relation_type: %w[infrastructure_exposure infrastructure_disruption], derived_by: RELATION_DERIVED_BY, target_node_type: "OntologyEntity")
        .to_a
        .reject { |relationship| desired_relationships.include?([relationship.target_node_id, relationship.relation_type]) }
        .map(&:id)
      return if stale_ids.empty?

      OntologyRelationshipEvidence.where(ontology_relationship_id: stale_ids).delete_all
      OntologyRelationship.where(id: stale_ids).delete_all
    end

    def infrastructure_disruption_event_key(payload)
      "event:#{payload.fetch(:kind).to_s.tr('_', '-')}:#{record_stable_identifier(payload.fetch(:record))}"
    end

    def record_stable_identifier(record)
      record.try(:external_id).presence || record.id
    end

    def infrastructure_disruption_confidence(payload, candidate)
      confidence = payload.fetch(:confidence).to_f * 0.55 + candidate.fetch(:confidence).to_f * 0.45
      confidence += 0.05 if payload.fetch(:severity).in?(%w[critical high])
      [confidence, 0.94].min.round(2)
    end

    def infrastructure_disruption_explanation(payload, candidate)
      "#{payload.fetch(:title)} occurred #{candidate.fetch(:distance_km).round(1)}km from #{candidate.fetch(:entity).canonical_name}, exposing #{candidate.fetch(:asset_type).to_s.tr('_', ' ')} infrastructure"
    end

    def repair_geoconfirmed_date_only_labels(now:)
      since = now - GEOCONFIRMED_LABEL_REPAIR_WINDOW
      repaired_count = 0

      OntologyEvent.includes(:place_entity)
        .where(event_type: "geoconfirmed_strike")
        .where("canonical_key LIKE ?", "event:geoconfirmed-strike:%")
        .where("last_seen_at >= ? OR updated_at >= ?", since, since)
        .find_each do |event|
          current_title = event.metadata.fetch("canonical_title", "").to_s.scrub("").squish
          next unless geoconfirmed_date_only_title?(current_title)

          geoconfirmed_event = geoconfirmed_evidence_for_event(event)
          next if geoconfirmed_event.blank?

          replacement_title = geoconfirmed_event_title(geoconfirmed_event)
          next if replacement_title.blank? || replacement_title == current_title

          event.metadata = event.metadata.merge("canonical_title" => replacement_title)
          event.save!
          repair_geoconfirmed_place_entity_label(event.place_entity, current_title, replacement_title)
          repair_geoconfirmed_relationship_explanations(event, current_title, replacement_title)
          repaired_count += 1
        end

      repaired_count
    end

    def geoconfirmed_evidence_for_event(event)
      evidence_link = event.ontology_evidence_links.find_by(evidence_type: "GeoconfirmedEvent")
      return if evidence_link.blank?

      GeoconfirmedEvent.find_by(id: evidence_link.evidence_id)
    end

    def repair_geoconfirmed_place_entity_label(place_entity, current_title, replacement_title)
      return if place_entity.blank?
      return unless place_entity.canonical_name.to_s.squish == current_title

      place_entity.update!(canonical_name: replacement_title)
      OntologySyncSupport.upsert_alias(place_entity, replacement_title, alias_type: "event_location")
    end

    def repair_geoconfirmed_relationship_explanations(event, current_title, replacement_title)
      event.outgoing_ontology_relationships
        .where(derived_by: RELATION_DERIVED_BY)
        .where("explanation LIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(current_title)}%")
        .find_each do |relationship|
          relationship.update!(explanation: relationship.explanation.to_s.gsub(current_title, replacement_title))
        end
    end
  end
end
