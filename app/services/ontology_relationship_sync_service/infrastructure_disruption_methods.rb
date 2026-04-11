class OntologyRelationshipSyncService
  module InfrastructureDisruptionMethods
    private

    def sync_infrastructure_disruption_relationships(now:)
      recent_infrastructure_disruption_events(now: now).sum do |payload|
        event = sync_infrastructure_disruption_event(payload)
        sync_hazard_asset_relationships(event: event, payload: payload, now: now)
      end
    end

    def recent_infrastructure_disruption_events(now:)
      recent_earthquakes(now: now) +
        recent_fire_hotspots(now: now) +
        recent_natural_disruption_events(now: now) +
        recent_geoconfirmed_kinetic_events(now: now) +
        recent_news_kinetic_events(now: now)
    end

    def recent_earthquakes(now:)
      Earthquake.where("event_time >= ?", now - INFRASTRUCTURE_DISRUPTION_EVENT_WINDOW)
        .where.not(latitude: nil, longitude: nil)
        .where("COALESCE(magnitude, 0) >= ? OR tsunami = ? OR alert IS NOT NULL", 5.0, true)
        .order(event_time: :desc)
        .limit(INFRASTRUCTURE_DISRUPTION_EVENT_LIMIT)
        .map do |earthquake|
          {
            kind: :earthquake,
            record: earthquake,
            title: earthquake.title.presence || "M#{earthquake.magnitude.to_f.round(1)} earthquake",
            text: earthquake.title.to_s,
            event_family: "disaster",
            event_type: "earthquake",
            latitude: earthquake.latitude.to_f,
            longitude: earthquake.longitude.to_f,
            observed_at: earthquake.event_time || earthquake.fetched_at || earthquake.updated_at,
            radius_km: earthquake_disruption_radius_km(earthquake),
            severity: earthquake_disruption_severity(earthquake),
            confidence: earthquake_event_confidence(earthquake),
          }
        end
    end

    def recent_fire_hotspots(now:)
      FireHotspot.where("acq_datetime >= ?", now - INFRASTRUCTURE_DISRUPTION_EVENT_WINDOW)
        .where.not(latitude: nil, longitude: nil)
        .order(acq_datetime: :desc)
        .limit(INFRASTRUCTURE_DISRUPTION_EVENT_LIMIT)
        .filter_map do |fire|
          next unless relevant_fire_hotspot?(fire)

          kinetic = possible_thermal_strike?(fire)
          {
            kind: kinetic ? :thermal_strike : :fire_hotspot,
            record: fire,
            title: kinetic ? "Thermal strike signal #{fire.external_id}" : "Fire hotspot #{fire.external_id}",
            text: fire.external_id.to_s,
            event_family: kinetic ? "conflict" : "disaster",
            event_type: kinetic ? "thermal_strike" : "fire_hotspot",
            latitude: fire.latitude.to_f,
            longitude: fire.longitude.to_f,
            observed_at: fire.acq_datetime || fire.fetched_at || fire.updated_at,
            radius_km: fire_disruption_radius_km(fire),
            severity: fire_disruption_severity(fire),
            confidence: fire_event_confidence(fire),
          }
        end
    end

    def recent_natural_disruption_events(now:)
      NaturalEvent.where("event_date >= ?", now - INFRASTRUCTURE_DISRUPTION_EVENT_WINDOW)
        .where.not(latitude: nil, longitude: nil)
        .where(category_title: INFRASTRUCTURE_DISRUPTION_NATURAL_EVENT_CATEGORIES)
        .order(event_date: :desc)
        .limit(INFRASTRUCTURE_DISRUPTION_EVENT_LIMIT)
        .map do |event|
          {
            kind: :natural_event,
            record: event,
            title: event.title.presence || event.category_title.presence || "Natural event",
            text: [event.title, event.category_title].compact.join(" "),
            event_family: "disaster",
            event_type: "natural_event",
            latitude: event.latitude.to_f,
            longitude: event.longitude.to_f,
            observed_at: event.event_date || event.fetched_at || event.updated_at,
            radius_km: natural_event_disruption_radius_km(event),
            severity: natural_event_disruption_severity(event),
            confidence: natural_event_confidence(event),
          }
        end
    end

    def recent_geoconfirmed_kinetic_events(now:)
      GeoconfirmedEvent.where("COALESCE(posted_at, event_time, fetched_at) >= ?", now - INFRASTRUCTURE_DISRUPTION_EVENT_WINDOW)
        .where.not(latitude: nil, longitude: nil)
        .order(Arel.sql("COALESCE(posted_at, event_time, fetched_at) DESC"))
        .limit(INFRASTRUCTURE_DISRUPTION_EVENT_LIMIT)
        .filter_map do |event|
          text = [event.title, event.description, event.icon_key].compact.join(" ")
          next unless kinetic_event_text?(text)

          {
            kind: :geoconfirmed_strike,
            record: event,
            title: event.title.presence || "GeoConfirmed kinetic event",
            text: text,
            event_family: "conflict",
            event_type: "geoconfirmed_strike",
            latitude: event.latitude.to_f,
            longitude: event.longitude.to_f,
            observed_at: event.posted_at || event.event_time || event.fetched_at || event.updated_at,
            radius_km: 45.0,
            severity: disruption_language?(text) ? "high" : "medium",
            confidence: 0.82,
          }
        end
    end

    def recent_news_kinetic_events(now:)
      NewsStoryCluster.where("last_seen_at >= ?", now - INFRASTRUCTURE_DISRUPTION_EVENT_WINDOW)
        .where(event_family: %w[conflict security infrastructure transport])
        .where(event_type: INFRASTRUCTURE_KINETIC_EVENT_TYPES)
        .where.not(latitude: nil, longitude: nil)
        .where("source_count >= ? OR verification_status IN (?)", 2, CORROBORATED_NEWS_STATUSES)
        .order(last_seen_at: :desc)
        .limit(INFRASTRUCTURE_DISRUPTION_EVENT_LIMIT)
        .map do |cluster|
          event = NewsOntologySyncService.sync_story_cluster(cluster)
          text = [cluster.canonical_title, cluster.location_name].compact.join(" ")
          {
            kind: :news_kinetic_event,
            record: cluster,
            ontology_event: event,
            title: cluster.canonical_title.presence || "Reported kinetic event",
            text: text,
            event_family: cluster.event_family,
            event_type: cluster.event_type,
            latitude: cluster.latitude.to_f,
            longitude: cluster.longitude.to_f,
            observed_at: cluster.last_seen_at || cluster.first_seen_at || cluster.updated_at,
            radius_km: 55.0,
            severity: disruption_language?(text) ? "high" : "medium",
            confidence: [cluster.cluster_confidence.to_f, 0.9].min,
          }
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
      event.metadata = {
        "canonical_title" => payload.fetch(:title),
        "event_kind" => payload.fetch(:kind).to_s,
        "event_type" => payload.fetch(:event_type, payload.fetch(:kind).to_s),
        "severity" => payload.fetch(:severity),
        "radius_km" => payload.fetch(:radius_km).round(1),
        "latitude" => payload.fetch(:latitude),
        "longitude" => payload.fetch(:longitude),
      }.compact
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

      created_count = candidates.count do |candidate|
        relation_type = infrastructure_relationship_type(payload, candidate)
        desired_relationships << [candidate.fetch(:entity).id, relation_type]
        relationship = OntologySyncSupport.upsert_relationship(
          source_node: event,
          target_node: candidate.fetch(:entity),
          relation_type: relation_type,
          confidence: infrastructure_disruption_confidence(payload, candidate),
          fresh_until: [payload.fetch(:observed_at), now].compact.max + INFRASTRUCTURE_DISRUPTION_FRESHNESS,
          derived_by: RELATION_DERIVED_BY,
          explanation: infrastructure_disruption_explanation(payload, candidate),
          metadata: {
            "event_kind" => payload.fetch(:kind).to_s,
            "event_type" => payload.fetch(:event_type, payload.fetch(:kind).to_s),
            "severity" => payload.fetch(:severity),
            "asset_type" => candidate.fetch(:asset_type).to_s,
            "distance_km" => candidate.fetch(:distance_km).round(1),
            "radius_km" => payload.fetch(:radius_km).round(1),
            "observed_at" => payload.fetch(:observed_at)&.iso8601,
          }.compact
        )

        sync_relationship_evidences(
          relationship,
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
        )
        true
      end

      stale_scope = event.outgoing_ontology_relationships
        .where(relation_type: %w[infrastructure_exposure infrastructure_disruption], derived_by: RELATION_DERIVED_BY, target_node_type: "OntologyEntity")
      stale_ids = stale_scope.to_a.reject do |relationship|
        desired_relationships.include?([relationship.target_node_id, relationship.relation_type])
      end.map(&:id)
      if stale_ids.any?
        OntologyRelationshipEvidence.where(ontology_relationship_id: stale_ids).delete_all
        OntologyRelationship.where(id: stale_ids).delete_all
      end

      created_count
    end

    def infrastructure_disruption_asset_candidates(payload, now:)
      lat = payload.fetch(:latitude)
      lng = payload.fetch(:longitude)
      radius_km = payload.fetch(:radius_km)

      (
        infrastructure_airport_candidates(lat: lat, lng: lng, radius_km: radius_km) +
        infrastructure_military_base_candidates(lat: lat, lng: lng, radius_km: radius_km) +
        infrastructure_port_candidates(lat: lat, lng: lng, radius_km: radius_km) +
        infrastructure_power_plant_candidates(lat: lat, lng: lng, radius_km: radius_km) +
        infrastructure_submarine_cable_candidates(lat: lat, lng: lng, radius_km: radius_km, now: now)
      ).sort_by { |candidate| [-candidate.fetch(:confidence), candidate.fetch(:distance_km), candidate.fetch(:entity).canonical_name] }
    end

    def infrastructure_airport_candidates(lat:, lng:, radius_km:)
      lat_range, lng_range = bbox_for_radius(lat, lng, radius_km)
      Airport.where(latitude: lat_range, longitude: lng_range)
        .where("is_military = ? OR airport_type IN (?)", true, %w[large_airport medium_airport military])
        .to_a
        .filter_map do |airport|
          distance = haversine_km(airport.latitude, airport.longitude, lat, lng)
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
        .first(INFRASTRUCTURE_DISRUPTION_ASSET_LIMITS.fetch(:airport))
    end

    def infrastructure_military_base_candidates(lat:, lng:, radius_km:)
      lat_range, lng_range = bbox_for_radius(lat, lng, radius_km)
      MilitaryBase.where(latitude: lat_range, longitude: lng_range)
        .to_a
        .filter_map do |base|
          distance = haversine_km(base.latitude, base.longitude, lat, lng)
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
        .first(INFRASTRUCTURE_DISRUPTION_ASSET_LIMITS.fetch(:military_base))
    end

    def infrastructure_power_plant_candidates(lat:, lng:, radius_km:)
      lat_range, lng_range = bbox_for_radius(lat, lng, radius_km)
      PowerPlant.where(latitude: lat_range, longitude: lng_range)
        .where("COALESCE(capacity_mw, 0) >= ? OR primary_fuel IN (?)", 100, %w[Nuclear Gas Oil Hydro Coal])
        .to_a
        .filter_map do |plant|
          distance = haversine_km(plant.latitude, plant.longitude, lat, lng)
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
        .first(INFRASTRUCTURE_DISRUPTION_ASSET_LIMITS.fetch(:power_plant))
    end

    def infrastructure_port_candidates(lat:, lng:, radius_km:)
      lat_range, lng_range = bbox_for_radius(lat, lng, radius_km)
      TradeLocation.active.where(location_kind: "port", latitude: lat_range, longitude: lng_range)
        .to_a
        .filter_map do |port|
          distance = haversine_km(port.latitude, port.longitude, lat, lng)
          next if distance > radius_km

          {
            asset_type: :port,
            record: port,
            entity: sync_port_entity(port),
            distance_km: distance,
            confidence: strategic_asset_confidence(:port, distance, radius_km, port_importance_bonus(port)),
          }
        end
        .sort_by { |candidate| [candidate.fetch(:distance_km), -port_importance_score(candidate.fetch(:record))] }
        .first(INFRASTRUCTURE_DISRUPTION_ASSET_LIMITS.fetch(:port))
    end

    def infrastructure_submarine_cable_candidates(lat:, lng:, radius_km:, now:)
      SubmarineCable.all
        .filter_map do |cable|
          distance = submarine_cable_distance_km(cable, lat, lng)
          next if distance.blank? || distance > radius_km

          supporting_outages = supporting_cable_outages(cable, now: now)
          {
            asset_type: :submarine_cable,
            record: cable,
            entity: sync_submarine_cable_entity(cable),
            distance_km: distance,
            confidence: strategic_asset_confidence(:submarine_cable, distance, radius_km, supporting_outages.any? ? 0.08 : 0.0),
            supporting_evidence: supporting_outages.map do |outage|
              {
                evidence: outage,
                evidence_role: "supporting_outage",
                confidence: OntologySyncSupport.normalized_confidence(outage.score),
                metadata: {
                  "entity_code" => outage.entity_code,
                  "level" => outage.level,
                  "started_at" => outage.started_at&.iso8601,
                }.compact,
              }
            end,
          }
        end
        .sort_by { |candidate| [candidate.fetch(:distance_km), candidate.fetch(:record).name.to_s] }
        .first(INFRASTRUCTURE_DISRUPTION_ASSET_LIMITS.fetch(:submarine_cable))
    end

    def infrastructure_relationship_type(payload, candidate)
      confirmed_infrastructure_disruption?(payload, candidate) ? "infrastructure_disruption" : "infrastructure_exposure"
    end

    def confirmed_infrastructure_disruption?(payload, candidate)
      asset_type = candidate.fetch(:asset_type)
      return Array(candidate[:supporting_evidence]).any? if asset_type == :submarine_cable

      distance = candidate.fetch(:distance_km).to_f
      radius = kinetic_disruption_radius_km(asset_type)
      return true if payload.fetch(:kind) == :thermal_strike && distance <= radius

      kinetic_event = %i[geoconfirmed_strike news_kinetic_event].include?(payload.fetch(:kind))
      kinetic_event && disruption_language?(payload[:text]) && distance <= (radius * 2.0)
    end

    def kinetic_disruption_radius_km(asset_type)
      {
        airport: 8.0,
        military_base: 10.0,
        port: 10.0,
        power_plant: 8.0,
      }.fetch(asset_type, 6.0)
    end

    def supporting_cable_outages(cable, now:)
      codes = cable_country_codes(cable)
      return [] if codes.empty?

      InternetOutage.where(entity_code: codes)
        .or(InternetOutage.where(entity_code: codes.map(&:downcase)))
        .where("COALESCE(started_at, fetched_at, updated_at) >= ?", now - INFRASTRUCTURE_DISRUPTION_EVENT_WINDOW)
        .order(Arel.sql("COALESCE(started_at, fetched_at, updated_at) DESC"))
        .limit(2)
        .to_a
    end

    def cable_country_codes(cable)
      Array(cable.landing_points).filter_map do |point|
        (point["country_code"] || point[:country_code] || point["country"] || point[:country]).to_s.upcase.presence
      end.uniq
    end

    def port_importance_score(port)
      metadata = port.metadata.is_a?(Hash) ? port.metadata : {}
      return metadata["importance"].to_f if metadata["importance"].present?
      return 0.82 if metadata["harbor_size"].to_s.casecmp?("large") || metadata["harbor_size"].to_s.casecmp?("l")
      return 0.66 if metadata["harbor_size"].to_s.casecmp?("medium") || metadata["harbor_size"].to_s.casecmp?("m")

      0.5
    end

    def port_importance_bonus(port)
      score = port_importance_score(port)
      [[score - 0.5, 0.0].max, 0.12].min
    end

    def infrastructure_disruption_event_key(payload)
      "event:#{payload.fetch(:kind).to_s.tr('_', '-')}:#{record_stable_identifier(payload.fetch(:record))}"
    end

    def record_stable_identifier(record)
      record.try(:external_id).presence || record.id
    end

    def earthquake_disruption_radius_km(earthquake)
      magnitude = earthquake.magnitude.to_f
      [[40.0 + (magnitude * 22.0), 90.0].max, 260.0].min
    end

    def fire_disruption_radius_km(fire)
      base = fire.frp.to_f >= 50.0 ? 45.0 : 25.0
      fire.confidence.to_s.in?(%w[high h]) || fire.confidence.to_f >= 80.0 ? base + 10.0 : base
    end

    def natural_event_disruption_radius_km(event)
      return 120.0 if event.category_title.to_s.in?(["Severe Storms", "Floods"])
      return 90.0 if event.category_title.to_s == "Volcanoes"

      60.0
    end

    def earthquake_disruption_severity(earthquake)
      return "critical" if earthquake.magnitude.to_f >= 7.0 || earthquake.alert == "red" || earthquake.tsunami?
      return "high" if earthquake.magnitude.to_f >= 6.0 || earthquake.alert.in?(%w[orange yellow])
      return "medium" if earthquake.magnitude.to_f >= 5.0

      "low"
    end

    def fire_disruption_severity(fire)
      return "high" if fire.confidence.to_s.in?(%w[high h]) && fire.frp.to_f >= 50.0
      return "medium" if fire.confidence.to_s.in?(%w[high h nominal n])
      return "medium" if fire.confidence.to_s.match?(/\A\d+(\.\d+)?\z/) && fire.confidence.to_f >= 60.0

      "low"
    end

    def natural_event_disruption_severity(event)
      return "high" if event.magnitude_value.to_f >= 5.0
      return "medium" if event.category_title.to_s.in?(["Volcanoes", "Wildfires", "Floods", "Severe Storms"])

      "low"
    end

    def earthquake_event_confidence(earthquake)
      confidence = 0.62
      confidence += [earthquake.magnitude.to_f / 10.0, 0.2].min
      confidence += 0.08 if earthquake.alert.present?
      confidence += 0.05 if earthquake.tsunami?
      [confidence, 0.92].min.round(2)
    end

    def fire_event_confidence(fire)
      confidence = fire.confidence.to_s.in?(%w[high h]) || fire.confidence.to_f >= 80.0 ? 0.76 : 0.62
      confidence += [fire.frp.to_f / 300.0, 0.1].min if fire.frp.present?
      [confidence, 0.9].min.round(2)
    end

    def relevant_fire_hotspot?(fire)
      confidence = fire.confidence.to_s.downcase
      return true if %w[high h nominal n].include?(confidence)
      return confidence.to_f >= 60.0 if confidence.match?(/\A\d+(\.\d+)?\z/)

      false
    end

    def possible_thermal_strike?(fire)
      return false unless fire.latitude.present? && fire.longitude.present?

      confidence = fire.confidence.to_s.downcase
      is_confident = %w[high h].include?(confidence) || confidence.to_f >= 80.0
      return false unless is_confident

      in_conflict_zone = Api::FireHotspotsController::CONFLICT_COUNTRIES.any? do |_code, bounds|
        bounds[:lat].cover?(fire.latitude) && bounds[:lng].cover?(fire.longitude)
      end
      return false unless in_conflict_zone

      fire.daynight == "N" || fire.frp.to_f > 20.0 || fire.brightness.to_f > 360.0
    end

    def kinetic_event_text?(text)
      text.to_s.match?(/\b(airstrike|missile|drone|shelling|strike|strikes|struck|attack|attacks|explosion|blast)\b/i)
    end

    def disruption_language?(text)
      text.to_s.match?(/\b(hit|struck|damag(?:e|ed|ing)?|destroy(?:ed|s)?|explosion|blast|fire|burn(?:ed|ing)?|closed|closure|halt(?:ed)?|suspend(?:ed)?|outage|blackout|shut(?:down)?|disabled|disrupt(?:ed|ion)?)\b/i)
    end

    def natural_event_confidence(event)
      confidence = 0.6
      confidence += 0.08 if event.sources.present?
      confidence += 0.05 if event.geometry_points.present?
      [confidence, 0.85].min.round(2)
    end

    def infrastructure_disruption_confidence(payload, candidate)
      confidence = payload.fetch(:confidence).to_f * 0.55 + candidate.fetch(:confidence).to_f * 0.45
      confidence += 0.05 if payload.fetch(:severity).in?(%w[critical high])
      [confidence, 0.94].min.round(2)
    end

    def infrastructure_disruption_explanation(payload, candidate)
      "#{payload.fetch(:title)} occurred #{candidate.fetch(:distance_km).round(1)}km from #{candidate.fetch(:entity).canonical_name}, exposing #{candidate.fetch(:asset_type).to_s.tr('_', ' ')} infrastructure"
    end
  end
end
