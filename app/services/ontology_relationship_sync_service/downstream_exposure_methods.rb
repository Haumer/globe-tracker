class OntologyRelationshipSyncService
  module DownstreamExposureMethods
    private

    def sync_downstream_exposure_relationships(theaters:, theater_entities:, chokepoint_entities:, corroborated_story_clusters:, now:)
      exposures_by_chokepoint = chokepoint_entities.each_with_object({}) do |(chokepoint_key, _entity), memo|
        memo[chokepoint_key] = strategic_asset_candidates_for_chokepoint(chokepoint_key)
      end

      relationship_count = sync_chokepoint_downstream_exposures(
        chokepoint_entities: chokepoint_entities,
        exposures_by_chokepoint: exposures_by_chokepoint,
        corroborated_story_clusters: corroborated_story_clusters,
        now: now
      )

      relationship_count + sync_theater_downstream_exposures(
        theaters: theaters,
        theater_entities: theater_entities,
        exposures_by_chokepoint: exposures_by_chokepoint,
        now: now
      )
    end

    def sync_chokepoint_downstream_exposures(chokepoint_entities:, exposures_by_chokepoint:, corroborated_story_clusters:, now:)
      chokepoint_entities.sum do |chokepoint_key, chokepoint_entity|
        chokepoint = ChokepointMonitorService::CHOKEPOINTS.fetch(chokepoint_key)
        story_evidence = direct_chokepoint_story_clusters(corroborated_story_clusters, chokepoint_key, chokepoint).first(2)

        exposures_by_chokepoint.fetch(chokepoint_key, []).count do |candidate|
          relationship = OntologySyncSupport.upsert_relationship(
            source_node: chokepoint_entity,
            target_node: candidate.fetch(:entity),
            relation_type: "downstream_exposure",
            confidence: candidate.fetch(:confidence),
            fresh_until: now + 24.hours,
            derived_by: RELATION_DERIVED_BY,
            explanation: chokepoint_downstream_explanation(chokepoint, candidate),
            metadata: {
              "source_kind" => "chokepoint",
              "chokepoint" => chokepoint_key.to_s,
              "asset_type" => candidate.fetch(:asset_type).to_s,
              "distance_km" => candidate.fetch(:distance_km).round(1),
            }
          )

          sync_relationship_evidences(
            relationship,
            [
              {
                evidence: candidate.fetch(:record),
                evidence_role: "exposed_asset",
                confidence: candidate.fetch(:confidence),
                metadata: {
                  "asset_type" => candidate.fetch(:asset_type).to_s,
                  "distance_km" => candidate.fetch(:distance_km).round(1),
                },
              },
            ] +
            story_evidence.map do |cluster|
              {
                evidence: cluster,
                evidence_role: "supporting_story",
                confidence: cluster.cluster_confidence.to_f,
                metadata: {
                  "source_count" => cluster.source_count.to_i,
                  "last_seen_at" => cluster.last_seen_at&.iso8601,
                },
              }
            end
          )
          true
        end
      end
    end

    def sync_theater_downstream_exposures(theaters:, theater_entities:, exposures_by_chokepoint:, now:)
      theaters.sum do |summary|
        theater_entity = theater_entities.fetch(summary.fetch(:name))
        target_keys = theater_pressure_target_keys(summary)

        grouped_candidates = target_keys.flat_map do |chokepoint_key|
          exposures_by_chokepoint.fetch(chokepoint_key, []).map do |candidate|
            candidate.merge(via_chokepoint_key: chokepoint_key)
          end
        end.group_by { |candidate| candidate.fetch(:entity).id }

        grouped_candidates.count do |_entity_id, candidates|
          primary_candidate = candidates.min_by { |candidate| candidate.fetch(:distance_km) }
          via_keys = candidates.map { |candidate| candidate.fetch(:via_chokepoint_key) }.uniq
          relationship = OntologySyncSupport.upsert_relationship(
            source_node: theater_entity,
            target_node: primary_candidate.fetch(:entity),
            relation_type: "downstream_exposure",
            confidence: theater_downstream_exposure_confidence(summary, primary_candidate, via_keys),
            fresh_until: [summary.fetch(:last_seen_at), now].compact.max + 6.hours,
            derived_by: RELATION_DERIVED_BY,
            explanation: theater_downstream_explanation(summary, primary_candidate, via_keys),
            metadata: {
              "source_kind" => "theater",
              "theater" => summary.fetch(:name),
              "via_chokepoints" => via_keys.map(&:to_s),
              "asset_type" => primary_candidate.fetch(:asset_type).to_s,
              "distance_km" => primary_candidate.fetch(:distance_km).round(1),
            }
          )

          sync_relationship_evidences(
            relationship,
            [
              {
                evidence: primary_candidate.fetch(:record),
                evidence_role: "exposed_asset",
                confidence: primary_candidate.fetch(:confidence),
                metadata: {
                  "asset_type" => primary_candidate.fetch(:asset_type).to_s,
                  "distance_km" => primary_candidate.fetch(:distance_km).round(1),
                },
              },
            ] +
            summary.fetch(:clusters).first(2).map do |cluster|
              {
                evidence: cluster,
                evidence_role: "supporting_story",
                confidence: cluster.cluster_confidence.to_f,
                metadata: {
                  "source_count" => cluster.source_count.to_i,
                  "last_seen_at" => cluster.last_seen_at&.iso8601,
                },
              }
            end
          )
          true
        end
      end
    end

    def strategic_asset_candidates_for_chokepoint(chokepoint_key)
      chokepoint = ChokepointMonitorService::CHOKEPOINTS.fetch(chokepoint_key)
      radius_km = downstream_search_radius_km(chokepoint)

      airport_candidates(chokepoint, radius_km) +
        military_base_candidates(chokepoint, radius_km) +
        power_plant_candidates(chokepoint, radius_km) +
        submarine_cable_candidates(chokepoint, radius_km)
    end

    def downstream_search_radius_km(chokepoint)
      [[chokepoint[:radius_km].to_f * 8.0, 250.0].max, 900.0].min
    end

    def airport_candidates(chokepoint, radius_km)
      lat_range, lng_range = bbox_for_radius(chokepoint[:lat], chokepoint[:lng], radius_km)
      Airport.where(latitude: lat_range, longitude: lng_range)
        .where("is_military = ? OR airport_type IN (?)", true, %w[large_airport military])
        .to_a
        .filter_map do |airport|
          distance = haversine_km(airport.latitude, airport.longitude, chokepoint[:lat], chokepoint[:lng])
          next if distance > radius_km

          {
            asset_type: :airport,
            record: airport,
            entity: sync_airport_entity(airport),
            distance_km: distance,
            confidence: strategic_asset_confidence(:airport, distance, radius_km, airport.is_military? ? 0.08 : 0.0),
          }
        end
        .sort_by { |candidate| [candidate.fetch(:distance_km), candidate.fetch(:record).name.to_s] }
        .first(DOWNSTREAM_ASSET_LIMITS.fetch(:airport))
    end

    def military_base_candidates(chokepoint, radius_km)
      lat_range, lng_range = bbox_for_radius(chokepoint[:lat], chokepoint[:lng], radius_km)
      MilitaryBase.where(latitude: lat_range, longitude: lng_range)
        .to_a
        .filter_map do |base|
          distance = haversine_km(base.latitude, base.longitude, chokepoint[:lat], chokepoint[:lng])
          next if distance > radius_km

          {
            asset_type: :military_base,
            record: base,
            entity: sync_military_base_entity(base),
            distance_km: distance,
            confidence: strategic_asset_confidence(:military_base, distance, radius_km),
          }
        end
        .sort_by { |candidate| [candidate.fetch(:distance_km), candidate.fetch(:record).name.to_s] }
        .first(DOWNSTREAM_ASSET_LIMITS.fetch(:military_base))
    end

    def power_plant_candidates(chokepoint, radius_km)
      lat_range, lng_range = bbox_for_radius(chokepoint[:lat], chokepoint[:lng], radius_km)
      PowerPlant.where(latitude: lat_range, longitude: lng_range)
        .where("COALESCE(capacity_mw, 0) >= ? OR primary_fuel IN (?)", 250, %w[Nuclear Gas Oil Hydro])
        .to_a
        .filter_map do |plant|
          distance = haversine_km(plant.latitude, plant.longitude, chokepoint[:lat], chokepoint[:lng])
          next if distance > radius_km

          {
            asset_type: :power_plant,
            record: plant,
            entity: sync_power_plant_entity(plant),
            distance_km: distance,
            confidence: strategic_asset_confidence(:power_plant, distance, radius_km),
          }
        end
        .sort_by { |candidate| [candidate.fetch(:distance_km), -(candidate.fetch(:record).capacity_mw || 0)] }
        .first(DOWNSTREAM_ASSET_LIMITS.fetch(:power_plant))
    end

    def submarine_cable_candidates(chokepoint, radius_km)
      SubmarineCable.find_each.filter_map do |cable|
        distance = submarine_cable_distance_km(cable, chokepoint[:lat], chokepoint[:lng])
        next if distance.blank? || distance > radius_km

        {
          asset_type: :submarine_cable,
          record: cable,
          entity: sync_submarine_cable_entity(cable),
          distance_km: distance,
          confidence: strategic_asset_confidence(:submarine_cable, distance, radius_km),
        }
      end
        .sort_by { |candidate| [candidate.fetch(:distance_km), candidate.fetch(:record).name.to_s] }
        .first(DOWNSTREAM_ASSET_LIMITS.fetch(:submarine_cable))
    end

    def strategic_air_activity_targets(theaters)
      grouped = {}

      theaters.each do |summary|
        theater_pressure_target_keys(summary).each do |chokepoint_key|
          strategic_asset_candidates_for_chokepoint(chokepoint_key)
            .select { |candidate| %i[airport military_base].include?(candidate.fetch(:asset_type)) }
            .each do |candidate|
              key = candidate.fetch(:entity).id
              grouped[key] ||= candidate.slice(:asset_type, :record, :entity).merge(
                latitude: candidate.fetch(:record).latitude,
                longitude: candidate.fetch(:record).longitude,
                theaters: [],
                via_chokepoints: []
              )
              grouped[key][:theaters] << summary.fetch(:name)
              grouped[key][:via_chokepoints] << chokepoint_key.to_s
            end
        end
      end

      grouped.values.each do |target|
        target[:theaters] = target.fetch(:theaters).uniq
        target[:via_chokepoints] = target.fetch(:via_chokepoints).uniq
      end
    end

    def sync_airport_entity(airport)
      OntologySyncSupport.upsert_entity(
        canonical_key: "airport:#{airport.icao_code.to_s.downcase}",
        entity_type: ASSET_ENTITY_TYPES.fetch(:airport),
        canonical_name: airport.name,
        country_code: airport.country_code,
        metadata: {
          "airport_type" => airport.airport_type,
          "iata_code" => airport.iata_code,
          "icao_code" => airport.icao_code,
          "municipality" => airport.municipality,
          "latitude" => airport.latitude,
          "longitude" => airport.longitude,
          "is_military" => airport.is_military,
        }.compact
      ).tap do |entity|
        OntologySyncSupport.upsert_alias(entity, airport.name, alias_type: "official")
        OntologySyncSupport.upsert_alias(entity, airport.icao_code, alias_type: "icao") if airport.icao_code.present?
        OntologySyncSupport.upsert_alias(entity, airport.iata_code, alias_type: "iata") if airport.iata_code.present?
        OntologySyncSupport.upsert_link(entity, airport, role: "strategic_airport", method: "ontology_relationship_sync_v1")
      end
    end

    def sync_military_base_entity(base)
      OntologySyncSupport.upsert_entity(
        canonical_key: "military-base:#{base.external_id}",
        entity_type: ASSET_ENTITY_TYPES.fetch(:military_base),
        canonical_name: base.name.presence || base.external_id,
        metadata: {
          "base_type" => base.base_type,
          "operator" => base.operator,
          "country" => base.country,
          "latitude" => base.latitude,
          "longitude" => base.longitude,
          "source" => base.source,
        }.compact
      ).tap do |entity|
        OntologySyncSupport.upsert_alias(entity, base.name, alias_type: "official") if base.name.present?
        OntologySyncSupport.upsert_alias(entity, base.external_id, alias_type: "external_id")
        OntologySyncSupport.upsert_link(entity, base, role: "strategic_base", method: "ontology_relationship_sync_v1")
      end
    end

    def sync_power_plant_entity(plant)
      OntologySyncSupport.upsert_entity(
        canonical_key: "power-plant:#{plant.gppd_idnr.to_s.downcase}",
        entity_type: ASSET_ENTITY_TYPES.fetch(:power_plant),
        canonical_name: plant.name,
        country_code: plant.country_code,
        metadata: {
          "primary_fuel" => plant.primary_fuel,
          "capacity_mw" => plant.capacity_mw,
          "owner" => plant.owner,
          "latitude" => plant.latitude,
          "longitude" => plant.longitude,
          "country_name" => plant.country_name,
        }.compact
      ).tap do |entity|
        OntologySyncSupport.upsert_alias(entity, plant.name, alias_type: "official")
        OntologySyncSupport.upsert_alias(entity, plant.gppd_idnr, alias_type: "external_id")
        OntologySyncSupport.upsert_link(entity, plant, role: "strategic_power_plant", method: "ontology_relationship_sync_v1")
      end
    end

    def sync_submarine_cable_entity(cable)
      OntologySyncSupport.upsert_entity(
        canonical_key: "submarine-cable:#{cable.cable_id}",
        entity_type: ASSET_ENTITY_TYPES.fetch(:submarine_cable),
        canonical_name: cable.name.presence || cable.cable_id,
        metadata: {
          "color" => cable.color,
          "landing_point_count" => Array(cable.landing_points).size,
          "country_codes" => Array(cable.landing_points).filter_map { |point| point["country_code"] || point[:country_code] }.uniq.presence,
        }.compact
      ).tap do |entity|
        OntologySyncSupport.upsert_alias(entity, cable.name, alias_type: "official") if cable.name.present?
        OntologySyncSupport.upsert_alias(entity, cable.cable_id, alias_type: "external_id") if cable.cable_id.present?
        OntologySyncSupport.upsert_link(entity, cable, role: "strategic_cable", method: "ontology_relationship_sync_v1")
      end
    end

    def sync_camera_entity(camera)
      OntologySyncSupport.upsert_entity(
        canonical_key: "asset:camera:#{camera.source}:#{camera.webcam_id}",
        entity_type: CAMERA_ENTITY_TYPE,
        canonical_name: camera.title.presence || camera.webcam_id,
        metadata: {
          "asset_kind" => "camera",
          "webcam_id" => camera.webcam_id,
          "source" => camera.source,
          "camera_type" => camera.camera_type,
          "city" => camera.city,
          "region" => camera.region,
          "country" => camera.country,
          "latitude" => camera.latitude,
          "longitude" => camera.longitude,
          "is_live" => camera.is_live,
          "fetched_at" => camera.fetched_at&.iso8601,
        }.compact
      ).tap do |entity|
        OntologySyncSupport.upsert_alias(entity, camera.title, alias_type: "official") if camera.title.present?
        OntologySyncSupport.upsert_alias(entity, camera.webcam_id, alias_type: "external_id")
        OntologySyncSupport.upsert_link(entity, camera, role: "observation_camera", method: RELATION_DERIVED_BY)
      end
    end

    def strategic_asset_confidence(asset_type, distance_km, radius_km, bonus = 0.0)
      base = {
        airport: 0.56,
        military_base: 0.62,
        power_plant: 0.58,
        submarine_cable: 0.64,
      }.fetch(asset_type, 0.55)
      proximity = 1.0 - [(distance_km.to_f / radius_km.to_f), 1.0].min
      [base + (proximity * 0.24) + bonus.to_f, 0.92].min.round(2)
    end

    def theater_downstream_exposure_confidence(summary, candidate, via_keys)
      confidence = candidate.fetch(:confidence)
      confidence += [summary.fetch(:cluster_count) / 10.0 * 0.08, 0.08].min
      confidence += [via_keys.size * 0.03, 0.06].min
      [confidence, 0.95].min.round(2)
    end

    def chokepoint_downstream_explanation(chokepoint, candidate)
      asset_name = candidate.fetch(:entity).canonical_name
      distance = candidate.fetch(:distance_km).round
      "#{asset_name} lies #{distance}km from #{chokepoint.fetch(:name)}, making it a downstream-exposed #{candidate.fetch(:asset_type).to_s.tr('_', ' ')}"
    end

    def theater_downstream_explanation(summary, candidate, via_keys)
      via_names = via_keys.map { |key| ChokepointMonitorService::CHOKEPOINTS.fetch(key).fetch(:name) }
      "#{summary.fetch(:name)} pressure on #{via_names.join(', ')} leaves #{candidate.fetch(:entity).canonical_name} exposed downstream"
    end

    def bbox_for_radius(lat, lng, radius_km)
      dlat = radius_km / 111.0
      dlng = radius_km / (111.0 * Math.cos(lat.to_f * Math::PI / 180)).abs
      [(lat - dlat)..(lat + dlat), (lng - dlng)..(lng + dlng)]
    end

    def submarine_cable_distance_km(cable, lat, lng)
      points = cable_coordinate_points(cable)
      return if points.empty?

      points.map { |point_lat, point_lng| haversine_km(point_lat, point_lng, lat, lng) }.min
    end

    def cable_coordinate_points(cable)
      landing_points = Array(cable.landing_points).filter_map do |point|
        point_lat = point["lat"] || point[:lat]
        point_lng = point["lng"] || point[:lng]
        next if point_lat.blank? || point_lng.blank?

        [point_lat.to_f, point_lng.to_f]
      end
      return landing_points if landing_points.any?

      extract_coordinate_pairs(cable.coordinates)
    end

    def extract_coordinate_pairs(value)
      return [] unless value.is_a?(Array)

      if value.length >= 2 && value.first.is_a?(Numeric) && value.second.is_a?(Numeric)
        [[value.second.to_f, value.first.to_f]]
      else
        value.flat_map { |entry| extract_coordinate_pairs(entry) }
      end
    end
  end
end
