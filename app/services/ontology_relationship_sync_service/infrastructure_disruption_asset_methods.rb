class OntologyRelationshipSyncService
  module InfrastructureDisruptionAssetMethods
    private

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
  end
end
