class OntologyRelationshipSyncService
  module LocalCorroborationMethods
    private

    def sync_local_corroboration_relationships(now:)
      candidate_events = OntologyEvent.includes(:place_entity, :primary_story_cluster)
        .where(event_type: CAMERA_CORROBORATION_EVENT_TYPES)
        .where("last_seen_at >= ?", now - CAMERA_CORROBORATION_WINDOW)

      candidate_events.sum do |event|
        camera_candidates = nearby_camera_candidates_for_event(event, now: now)
        desired_target_ids = []

        created_count = camera_candidates.first(CAMERA_CORROBORATION_LIMIT).count do |candidate|
          camera = candidate.fetch(:record)
          camera_entity = candidate.fetch(:entity)
          desired_target_ids << camera_entity.id

          relationship = OntologySyncSupport.upsert_relationship(
            source_node: event,
            target_node: camera_entity,
            relation_type: "local_corroboration",
            confidence: candidate.fetch(:confidence),
            fresh_until: (camera.fetched_at || camera.updated_at) + CAMERA_CORROBORATION_MAX_AGE,
            derived_by: RELATION_DERIVED_BY,
            explanation: local_corroboration_explanation(event, camera, candidate),
            metadata: {
              "source_kind" => "event",
              "target_kind" => "camera",
              "distance_km" => candidate.fetch(:distance_km).round(1),
              "freshness_seconds" => candidate.fetch(:freshness_seconds),
              "camera_source" => camera.source,
              "camera_mode" => camera.is_live? ? "live" : "periodic",
            }.compact
          )

          sync_relationship_evidences(
            relationship,
            local_corroboration_evidence_payloads(event, candidate)
          )
          true
        end

        stale_scope = event.outgoing_ontology_relationships
          .where(relation_type: "local_corroboration", derived_by: RELATION_DERIVED_BY, target_node_type: "OntologyEntity")
        stale_scope = if desired_target_ids.any?
          stale_scope.where.not(target_node_id: desired_target_ids)
        else
          stale_scope
        end
        stale_scope.delete_all

        created_count
      end
    end

    def nearby_camera_candidates_for_event(event, now:)
      lat, lng = event_coordinates(event)
      return [] if lat.blank? || lng.blank?

      lat_range, lng_range = bbox_for_radius(lat, lng, CAMERA_CORROBORATION_RADIUS_KM)
      Camera.fresh
        .alive
        .where(latitude: lat_range, longitude: lng_range)
        .where("fetched_at >= ?", now - CAMERA_CORROBORATION_MAX_AGE)
        .filter_map do |camera|
          distance = haversine_km(camera.latitude, camera.longitude, lat, lng)
          next if distance > CAMERA_CORROBORATION_RADIUS_KM

          freshness_seconds = [(now - camera.fetched_at).to_i, 0].max if camera.fetched_at.present?
          {
            record: camera,
            entity: sync_camera_entity(camera),
            distance_km: distance,
            freshness_seconds: freshness_seconds,
            confidence: camera_corroboration_confidence(camera, distance, freshness_seconds),
          }
        end
        .sort_by { |candidate| [-candidate.fetch(:confidence), candidate.fetch(:distance_km), candidate.fetch(:record).title.to_s] }
    end

    def event_coordinates(event)
      cluster = event.primary_story_cluster
      if cluster&.latitude.present? && cluster&.longitude.present?
        return [cluster.latitude.to_f, cluster.longitude.to_f]
      end

      place = event.place_entity
      lat = place&.metadata&.dig("latitude")
      lng = place&.metadata&.dig("longitude")
      return [lat.to_f, lng.to_f] if lat.present? && lng.present?

      [nil, nil]
    end

    def camera_corroboration_confidence(camera, distance_km, freshness_seconds)
      freshness_ratio = if freshness_seconds.present?
        1.0 - [(freshness_seconds.to_f / CAMERA_CORROBORATION_MAX_AGE), 1.0].min
      else
        0.0
      end

      confidence = 0.52
      confidence += (1.0 - [(distance_km / CAMERA_CORROBORATION_RADIUS_KM), 1.0].min) * 0.18
      confidence += freshness_ratio * 0.14
      confidence += 0.08 if camera.source.in?(%w[youtube nycdot])
      confidence += 0.05 if camera.is_live?
      [confidence, 0.92].min.round(2)
    end

    def local_corroboration_explanation(event, camera, candidate)
      event_name = event.metadata["canonical_title"].presence || event.primary_story_cluster&.canonical_title || event.canonical_key
      description = "#{camera.title.presence || camera.webcam_id} is #{candidate.fetch(:distance_km).round(1)}km from #{event_name}"
      if candidate[:freshness_seconds].present?
        minutes = (candidate.fetch(:freshness_seconds) / 60.0).round
        description << " and was refreshed #{minutes}m ago"
      end
      description
    end

    def local_corroboration_evidence_payloads(event, candidate)
      payloads = [
        {
          evidence: candidate.fetch(:record),
          evidence_role: "observation_camera",
          confidence: candidate.fetch(:confidence),
          metadata: {
            "distance_km" => candidate.fetch(:distance_km).round(1),
            "freshness_seconds" => candidate.fetch(:freshness_seconds),
            "source" => candidate.fetch(:record).source,
            "is_live" => candidate.fetch(:record).is_live,
          }.compact,
        },
      ]

      cluster = event.primary_story_cluster
      if cluster.present?
        payloads << {
          evidence: cluster,
          evidence_role: "supporting_story",
          confidence: cluster.cluster_confidence.to_f,
          metadata: {
            "source_count" => cluster.source_count.to_i,
            "last_seen_at" => cluster.last_seen_at&.iso8601,
          }.compact,
        }
      end

      payloads
    end
  end
end
