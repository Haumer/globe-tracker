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
        assessment = infrastructure_relationship_assessment(payload, candidate)
        relation_type = assessment.fetch(:relation_type)
        candidate = candidate.merge(assessment)
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
        "impact_basis" => candidate.fetch(:impact_basis),
        "impact_status" => candidate.fetch(:impact_status),
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
      title = payload.fetch(:title)
      asset_name = candidate.fetch(:entity).canonical_name
      distance = candidate.fetch(:distance_km).round(1)
      asset_type = candidate.fetch(:asset_type).to_s.tr("_", " ")

      case candidate.fetch(:impact_basis)
      when "corroborated_operational_signal"
        "#{title} has corroborating operational evidence for #{asset_name}, indicating #{asset_type} disruption"
      when "direct_asset_reference"
        "#{title} directly references #{asset_name}, indicating likely #{asset_type} disruption"
      when "tight_thermal_signal"
        "#{title} was detected #{distance}km from #{asset_name}, a tight thermal signal indicating likely #{asset_type} disruption"
      else
        "#{title} occurred #{distance}km from #{asset_name}, exposing #{asset_type} infrastructure"
      end
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

    def repair_infrastructure_relationship_semantics(now:)
      since = now - GEOCONFIRMED_LABEL_REPAIR_WINDOW
      event_ids = OntologyEvent
        .where(event_type: %w[geoconfirmed_strike thermal_strike fire_hotspot natural_event earthquake])
        .where("last_seen_at >= ? OR updated_at >= ?", since, since)
        .pluck(:id)
      return 0 if event_ids.empty?

      repaired_count = 0
      OntologyRelationship.includes(:source_node, :target_node, :ontology_relationship_evidences)
        .where(source_node_type: "OntologyEvent", source_node_id: event_ids, target_node_type: "OntologyEntity")
        .where(relation_type: %w[infrastructure_disruption infrastructure_exposure], derived_by: RELATION_DERIVED_BY)
        .find_each do |relationship|
          event = relationship.source_node
          target = relationship.target_node
          next if event.blank? || target.blank?

          payload = infrastructure_repair_payload(event, relationship)
          candidate = infrastructure_repair_candidate(target, relationship)
          assessment = infrastructure_relationship_assessment(payload, candidate)
          next if infrastructure_semantics_current?(relationship, assessment)

          update_infrastructure_relationship_semantics!(relationship, payload, candidate.merge(assessment))
          repaired_count += 1
        end

      repaired_count
    end

    def infrastructure_repair_payload(event, relationship)
      evidence_text = relationship.ontology_relationship_evidences.filter_map do |link|
        next unless link.evidence_type == "GeoconfirmedEvent"

        [link.evidence.try(:title), link.evidence.try(:description), link.evidence.try(:icon_key)].compact.join(" ")
      end.join(" ")

      {
        kind: event.metadata["event_kind"].presence&.to_sym || event.event_type.to_s.to_sym,
        title: event.metadata["canonical_title"].presence || event.canonical_key,
        text: [event.metadata["canonical_title"], evidence_text, event.event_type].compact.join(" "),
        severity: event.metadata["severity"].presence || "medium",
        observed_at: event.last_seen_at || event.first_seen_at || event.started_at || event.updated_at,
        radius_km: relationship.metadata["radius_km"].presence || event.metadata["radius_km"].presence || 0.0,
      }
    end

    def infrastructure_repair_candidate(target, relationship)
      {
        entity: target,
        record: target,
        asset_type: relationship.metadata["asset_type"].presence&.to_sym || target.entity_type.to_s.to_sym,
        distance_km: relationship.metadata["distance_km"].to_f,
        confidence: relationship.confidence,
        supporting_evidence: relationship.ontology_relationship_evidences.select do |link|
          link.evidence_role.to_s.start_with?("supporting_")
        end,
      }
    end

    def infrastructure_semantics_current?(relationship, assessment)
      relationship.relation_type == assessment.fetch(:relation_type) &&
        relationship.metadata["impact_basis"] == assessment.fetch(:impact_basis) &&
        relationship.metadata["impact_status"] == assessment.fetch(:impact_status)
    end

    def update_infrastructure_relationship_semantics!(relationship, payload, candidate)
      relationship.update!(
        relation_type: candidate.fetch(:relation_type),
        explanation: infrastructure_disruption_explanation(payload, candidate),
        metadata: relationship.metadata.merge(
          "impact_basis" => candidate.fetch(:impact_basis),
          "impact_status" => candidate.fetch(:impact_status)
        )
      )
    rescue ActiveRecord::RecordNotUnique
      OntologyRelationshipEvidence.where(ontology_relationship_id: relationship.id).delete_all
      relationship.destroy!
    end
  end
end
