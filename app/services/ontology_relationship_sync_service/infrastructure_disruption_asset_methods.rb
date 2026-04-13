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

    def infrastructure_relationship_assessment(payload, candidate)
      basis = infrastructure_impact_basis(payload, candidate)
      if basis.present?
        {
          relation_type: "infrastructure_disruption",
          impact_basis: basis,
          impact_status: basis == "corroborated_operational_signal" ? "confirmed_disrupted" : "likely_disrupted",
        }
      else
        {
          relation_type: "infrastructure_exposure",
          impact_basis: "proximity_only",
          impact_status: "exposed",
        }
      end
    end

    def infrastructure_impact_basis(payload, candidate)
      asset_type = candidate.fetch(:asset_type)
      return "corroborated_operational_signal" if Array(candidate[:supporting_evidence]).any?
      return "direct_asset_reference" if directly_referenced_asset_impact?(payload, candidate)
      return "tight_thermal_signal" if tight_thermal_signal?(payload, candidate)

      nil
    end

    def directly_referenced_asset_impact?(payload, candidate)
      return false unless disruption_language?(payload[:text])

      asset_directly_referenced?(payload, candidate)
    end

    def tight_thermal_signal?(payload, candidate)
      return false unless payload.fetch(:kind) == :thermal_strike

      asset_type = candidate.fetch(:asset_type)
      return false if asset_type == :submarine_cable

      candidate.fetch(:distance_km).to_f <= tight_thermal_signal_radius_km(asset_type)
    end

    def tight_thermal_signal_radius_km(asset_type)
      {
        airport: 1.5,
        military_base: 1.5,
        port: 1.5,
        power_plant: 1.5,
      }.fetch(asset_type, 1.0)
    end

    def asset_directly_referenced?(payload, candidate)
      text = normalize_asset_reference_text([payload[:title], payload[:text]].compact.join(" "))
      return false if text.blank?

      asset_reference_terms(candidate).any? do |term|
        normalized_term = normalize_asset_reference_text(term)
        normalized_term.length >= 5 && text.include?(normalized_term)
      end
    end

    def asset_reference_terms(candidate)
      entity = candidate.fetch(:entity)
      record = candidate.fetch(:record)
      [
        entity.canonical_name,
        entity.try(:canonical_key),
        *entity.ontology_entity_aliases.pluck(:name),
        record.try(:name),
        record.try(:normalized_name),
        record.try(:icao_code),
        record.try(:iata_code),
        record.try(:locode),
        record.try(:gppd_idnr),
        record.try(:external_id),
        record.try(:cable_id),
      ].compact_blank.uniq
    end

    def normalize_asset_reference_text(value)
      value.to_s.downcase.gsub(/[^\p{Alnum}]+/, " ").squish
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
