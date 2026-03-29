class OntologyRelationshipSyncService
  module OperationalActivityMethods
    private

    def sync_operational_activity_relationships(theaters:, theater_entities:, chokepoint_entities:, corroborated_story_clusters:, now:)
      recent_jamming = recent_jamming_zones(now: now)
      recent_notams = recent_operational_notams(now: now)
      air_targets = strategic_air_activity_targets(theaters)
      theaters_by_name = theaters.index_by { |summary| summary.fetch(:name) }

      sync_chokepoint_ship_activity(
        chokepoint_entities: chokepoint_entities,
        corroborated_story_clusters: corroborated_story_clusters,
        now: now
      ) +
        sync_submarine_cable_ship_activity(now: now) +
        sync_theater_flight_activity(
          theaters: theaters,
          theater_entities: theater_entities,
          recent_jamming: recent_jamming,
          recent_notams: recent_notams,
          now: now
        ) +
        sync_strategic_air_asset_flight_activity(
          air_targets: air_targets,
          theaters_by_name: theaters_by_name,
          recent_jamming: recent_jamming,
          recent_notams: recent_notams,
          now: now
        )
    end

    def sync_chokepoint_ship_activity(chokepoint_entities:, corroborated_story_clusters:, now:)
      recent_ships = Ship.where("updated_at >= ?", now - RECENT_SHIP_WINDOW)
        .where.not(latitude: nil, longitude: nil)

      chokepoint_entities.sum do |chokepoint_key, chokepoint_entity|
        chokepoint = ChokepointMonitorService::CHOKEPOINTS.fetch(chokepoint_key)
        radius_km = chokepoint_ship_radius_km(chokepoint)
        lat_range, lng_range = bbox_for_radius(chokepoint[:lat], chokepoint[:lng], radius_km)
        story_evidence = direct_chokepoint_story_clusters(corroborated_story_clusters, chokepoint_key, chokepoint).first(1)

        candidates = recent_ships.where(latitude: lat_range, longitude: lng_range).filter_map do |ship|
          freshness_tier = operational_freshness_tier(
            ship.updated_at,
            now: now,
            live_window: LIVE_SHIP_WINDOW,
            recent_window: RECENT_SHIP_WINDOW
          )
          next if freshness_tier.blank?

          distance = haversine_km(ship.latitude, ship.longitude, chokepoint[:lat], chokepoint[:lng])
          next if distance > radius_km

          {
            record: ship,
            entity: OperationalOntologySyncService.sync_ship(ship),
            distance_km: distance,
            freshness_tier: freshness_tier,
            confidence: chokepoint_ship_activity_confidence(
              ship,
              distance,
              radius_km,
              story_evidence.present?,
              freshness_tier: freshness_tier
            ),
          }
        end

        candidates
          .sort_by { |candidate| [-candidate.fetch(:confidence), candidate.fetch(:distance_km), candidate.fetch(:record).name.to_s] }
          .first(OPERATIONAL_ACTIVITY_LIMITS.fetch(:chokepoint_ship))
          .count do |candidate|
            ship = candidate.fetch(:record)
            relationship = OntologySyncSupport.upsert_relationship(
              source_node: candidate.fetch(:entity),
              target_node: chokepoint_entity,
              relation_type: "operational_activity",
              confidence: candidate.fetch(:confidence),
              fresh_until: operational_relationship_fresh_until(
                ship.updated_at,
                freshness_tier: candidate.fetch(:freshness_tier),
                live_window: LIVE_SHIP_WINDOW,
                recent_window: RECENT_SHIP_WINDOW
              ),
              derived_by: RELATION_DERIVED_BY,
              explanation: chokepoint_ship_activity_explanation(ship, chokepoint, candidate.fetch(:distance_km), candidate.fetch(:freshness_tier)),
              metadata: {
                "source_kind" => "ship",
                "target_kind" => "chokepoint",
                "distance_km" => candidate.fetch(:distance_km).round(1),
                "freshness_tier" => candidate.fetch(:freshness_tier),
                "observed_at" => ship.updated_at&.iso8601,
                "speed_knots" => ship.speed&.round(1),
                "heading" => ship.heading&.round(1),
                "destination" => ship.destination,
                "flag" => ship.flag,
                "chokepoint" => chokepoint_key.to_s,
              }.compact
            )

            sync_relationship_evidences(
              relationship,
              [
                ship_operational_evidence_payload(
                  ship,
                  candidate.fetch(:confidence),
                  freshness_tier: candidate.fetch(:freshness_tier)
                ),
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

    def sync_submarine_cable_ship_activity(now:)
      recent_ships = Ship.where("updated_at >= ? AND COALESCE(speed, 0) >= 0 AND COALESCE(speed, 0) <= ?", now - RECENT_SHIP_WINDOW, 2.0)
        .where.not(latitude: nil, longitude: nil)

      candidates = recent_ships.filter_map do |ship|
        freshness_tier = operational_freshness_tier(
          ship.updated_at,
          now: now,
          live_window: LIVE_SHIP_WINDOW,
          recent_window: RECENT_SHIP_WINDOW
        )
        next if freshness_tier.blank?

        closest_cable = SubmarineCable.find_each.filter_map do |cable|
          distance = submarine_cable_distance_km(cable, ship.latitude, ship.longitude)
          next if distance.blank?

          { cable: cable, distance_km: distance }
        end.min_by { |payload| payload.fetch(:distance_km) }
        next if closest_cable.blank?
        next if closest_cable.fetch(:distance_km) > SHIP_CABLE_DISTANCE_KM

        {
          record: ship,
          entity: OperationalOntologySyncService.sync_ship(ship),
          cable: closest_cable.fetch(:cable),
          cable_entity: sync_submarine_cable_entity(closest_cable.fetch(:cable)),
          distance_km: closest_cable.fetch(:distance_km),
          freshness_tier: freshness_tier,
          confidence: submarine_cable_ship_activity_confidence(
            ship,
            closest_cable.fetch(:distance_km),
            freshness_tier: freshness_tier
          ),
        }
      end

      candidates
        .sort_by { |candidate| [-candidate.fetch(:confidence), candidate.fetch(:distance_km), candidate.fetch(:record).name.to_s] }
        .first(OPERATIONAL_ACTIVITY_LIMITS.fetch(:cable_ship))
        .count do |candidate|
          ship = candidate.fetch(:record)
          cable = candidate.fetch(:cable)
          relationship = OntologySyncSupport.upsert_relationship(
            source_node: candidate.fetch(:entity),
            target_node: candidate.fetch(:cable_entity),
            relation_type: "operational_activity",
            confidence: candidate.fetch(:confidence),
            fresh_until: operational_relationship_fresh_until(
              ship.updated_at,
              freshness_tier: candidate.fetch(:freshness_tier),
              live_window: LIVE_SHIP_WINDOW,
              recent_window: RECENT_SHIP_WINDOW
            ),
            derived_by: RELATION_DERIVED_BY,
            explanation: submarine_cable_ship_activity_explanation(ship, cable, candidate.fetch(:distance_km), candidate.fetch(:freshness_tier)),
            metadata: {
              "source_kind" => "ship",
              "target_kind" => "submarine_cable",
              "distance_km" => candidate.fetch(:distance_km).round(1),
              "freshness_tier" => candidate.fetch(:freshness_tier),
              "observed_at" => ship.updated_at&.iso8601,
              "speed_knots" => ship.speed&.round(1),
              "flag" => ship.flag,
              "destination" => ship.destination,
            }.compact
          )

          sync_relationship_evidences(
            relationship,
            [
              ship_operational_evidence_payload(
                ship,
                candidate.fetch(:confidence),
                freshness_tier: candidate.fetch(:freshness_tier)
              ),
            ]
          )
          true
        end
    end

    def sync_theater_flight_activity(theaters:, theater_entities:, recent_jamming:, recent_notams:, now:)
      theaters.sum do |summary|
        theater_entity = theater_entities.fetch(summary.fetch(:name))

        theater_flight_candidates(
          summary,
          recent_jamming: recent_jamming,
          recent_notams: recent_notams,
          now: now
        ).count do |candidate|
          flight = candidate.fetch(:record)
          relationship = OntologySyncSupport.upsert_relationship(
            source_node: candidate.fetch(:entity),
            target_node: theater_entity,
            relation_type: "operational_activity",
            confidence: candidate.fetch(:confidence),
            fresh_until: operational_relationship_fresh_until(
              flight.updated_at,
              freshness_tier: candidate.fetch(:freshness_tier),
              live_window: LIVE_FLIGHT_WINDOW,
              recent_window: RECENT_FLIGHT_WINDOW
            ),
            derived_by: RELATION_DERIVED_BY,
            explanation: theater_flight_activity_explanation(summary, candidate),
            metadata: {
              "source_kind" => "flight",
              "target_kind" => "theater",
              "theater" => summary.fetch(:name),
              "distance_km" => candidate.fetch(:distance_km).round(1),
              "freshness_tier" => candidate.fetch(:freshness_tier),
              "observed_at" => flight.updated_at&.iso8601,
              "military" => flight.military,
              "emergency" => emergency_flight?(flight),
              "jamming_pct" => candidate.dig(:jamming, :percentage)&.round(1),
              "notam_reason" => candidate.dig(:notam, :reason),
            }.compact
          )

          sync_relationship_evidences(
            relationship,
            flight_activity_evidence_payloads(flight, candidate, summary.fetch(:clusters).first(1))
          )
          true
        end
      end
    end

    def sync_strategic_air_asset_flight_activity(air_targets:, theaters_by_name:, recent_jamming:, recent_notams:, now:)
      air_targets.sum do |target|
        recent_flights_near_coordinates(
          lat: target.fetch(:latitude),
          lng: target.fetch(:longitude),
          radius_km: FLIGHT_STRATEGIC_ASSET_RADIUS_KM,
          now: now
        ).filter_map do |flight|
          freshness_tier = operational_freshness_tier(
            flight.updated_at,
            now: now,
            live_window: LIVE_FLIGHT_WINDOW,
            recent_window: RECENT_FLIGHT_WINDOW
          )
          next if freshness_tier.blank?

          jamming = nearest_jamming_signal(flight.latitude, flight.longitude, recent_jamming)
          notam = nearest_operational_notam(flight.latitude, flight.longitude, recent_notams)
          next unless heightened_flight_activity?(flight, jamming: jamming, notam: notam)

          distance = haversine_km(flight.latitude, flight.longitude, target.fetch(:latitude), target.fetch(:longitude))
          {
            record: flight,
            entity: OperationalOntologySyncService.sync_flight(flight),
            target: target,
            distance_km: distance,
            freshness_tier: freshness_tier,
            jamming: jamming,
            notam: notam,
            confidence: strategic_air_asset_flight_confidence(flight, distance, jamming, notam, freshness_tier: freshness_tier),
          }
        end
          .sort_by { |candidate| [-candidate.fetch(:confidence), candidate.fetch(:distance_km), candidate.fetch(:record).callsign.to_s] }
          .first(OPERATIONAL_ACTIVITY_LIMITS.fetch(:strategic_air_asset_flight))
          .count do |candidate|
            flight = candidate.fetch(:record)
            target = candidate.fetch(:target)
            supporting_clusters = target.fetch(:theaters).flat_map do |name|
              Array(theaters_by_name.dig(name, :clusters)).first(1)
            end.uniq.first(1)

            relationship = OntologySyncSupport.upsert_relationship(
              source_node: candidate.fetch(:entity),
              target_node: target.fetch(:entity),
              relation_type: "operational_activity",
              confidence: candidate.fetch(:confidence),
              fresh_until: operational_relationship_fresh_until(
                flight.updated_at,
                freshness_tier: candidate.fetch(:freshness_tier),
                live_window: LIVE_FLIGHT_WINDOW,
                recent_window: RECENT_FLIGHT_WINDOW
              ),
              derived_by: RELATION_DERIVED_BY,
              explanation: strategic_air_asset_flight_explanation(target, candidate),
              metadata: {
                "source_kind" => "flight",
                "target_kind" => target.fetch(:asset_type).to_s,
                "distance_km" => candidate.fetch(:distance_km).round(1),
                "freshness_tier" => candidate.fetch(:freshness_tier),
                "observed_at" => flight.updated_at&.iso8601,
                "military" => flight.military,
                "emergency" => emergency_flight?(flight),
                "jamming_pct" => candidate.dig(:jamming, :percentage)&.round(1),
                "notam_reason" => candidate.dig(:notam, :reason),
                "theaters" => target.fetch(:theaters),
                "via_chokepoints" => target.fetch(:via_chokepoints),
              }.compact
            )

            sync_relationship_evidences(
              relationship,
              flight_activity_evidence_payloads(flight, candidate, supporting_clusters)
            )
            true
          end
      end
    end

    def recent_jamming_zones(now:)
      GpsJammingSnapshot.where("recorded_at >= ? AND percentage >= ?", now - RECENT_JAMMING_WINDOW, 10.0)
    end

    def recent_operational_notams(now:)
      Notam.active
        .where(reason: OPERATIONAL_NOTAM_REASONS)
        .where.not(latitude: nil, longitude: nil)
        .where("effective_start >= ? OR fetched_at >= ?", now - RECENT_NOTAM_WINDOW, now - 12.hours)
    end

    def chokepoint_ship_radius_km(chokepoint)
      [[chokepoint[:radius_km].to_f * 2.5, CHOKEPOINT_SHIP_DISTANCE_MIN_KM].max, CHOKEPOINT_SHIP_DISTANCE_MAX_KM].min
    end

    def theater_flight_candidates(summary, recent_jamming:, recent_notams:, now:)
      points = summary.fetch(:clusters).filter_map do |cluster|
        next if cluster.latitude.blank? || cluster.longitude.blank?

        [cluster.latitude.to_f, cluster.longitude.to_f]
      end
      return [] if points.empty?

      bounds = bounds_for_points(points, FLIGHT_THEATER_RADIUS_KM)
      recent_flights = Flight.within_bounds(bounds)
        .where("updated_at >= ?", now - RECENT_FLIGHT_WINDOW)
        .where.not(latitude: nil, longitude: nil)

      recent_flights.filter_map do |flight|
        _nearest_point, distance = nearest_point_distance(flight.latitude, flight.longitude, points)
        next if distance > FLIGHT_THEATER_RADIUS_KM

        freshness_tier = operational_freshness_tier(
          flight.updated_at,
          now: now,
          live_window: LIVE_FLIGHT_WINDOW,
          recent_window: RECENT_FLIGHT_WINDOW
        )
        next if freshness_tier.blank?

        jamming = nearest_jamming_signal(flight.latitude, flight.longitude, recent_jamming)
        notam = nearest_operational_notam(flight.latitude, flight.longitude, recent_notams)
        next unless heightened_flight_activity?(flight, jamming: jamming, notam: notam)

        {
          record: flight,
          entity: OperationalOntologySyncService.sync_flight(flight),
          distance_km: distance,
          freshness_tier: freshness_tier,
          jamming: jamming,
          notam: notam,
          confidence: theater_flight_activity_confidence(flight, distance, jamming, notam, freshness_tier: freshness_tier),
        }
      end
        .sort_by { |candidate| [-candidate.fetch(:confidence), candidate.fetch(:distance_km), candidate.fetch(:record).callsign.to_s] }
        .first(OPERATIONAL_ACTIVITY_LIMITS.fetch(:theater_flight))
    end

    def recent_flights_near_coordinates(lat:, lng:, radius_km:, now:)
      lat_range, lng_range = bbox_for_radius(lat, lng, radius_km)
      Flight.where("updated_at >= ?", now - RECENT_FLIGHT_WINDOW)
        .where(latitude: lat_range, longitude: lng_range)
        .where.not(latitude: nil, longitude: nil)
    end

    def heightened_flight_activity?(flight, jamming:, notam:)
      flight.military? || emergency_flight?(flight) || jamming.present? || notam.present?
    end

    def emergency_flight?(flight)
      %w[7500 7600 7700].include?(flight.squawk.to_s) ||
        (flight.emergency.present? && flight.emergency.to_s.downcase != "none")
    end

    def nearest_jamming_signal(lat, lng, zones)
      zones.filter_map do |zone|
        next if zone.cell_lat.blank? || zone.cell_lng.blank?

        distance = haversine_km(lat, lng, zone.cell_lat, zone.cell_lng)
        next if distance > JAMMING_SIGNAL_DISTANCE_KM

        { record: zone, distance_km: distance, percentage: zone.percentage.to_f, level: zone.level }
      end.min_by { |payload| payload.fetch(:distance_km) }
    end

    def nearest_operational_notam(lat, lng, notams)
      notams.filter_map do |notam|
        distance = haversine_km(lat, lng, notam.latitude, notam.longitude)
        next if distance > notam_activity_radius_km(notam)

        { record: notam, distance_km: distance, reason: notam.reason }
      end.min_by { |payload| payload.fetch(:distance_km) }
    end

    def notam_activity_radius_km(notam)
      radius_from_m = notam.radius_m.to_f / 1000.0 if notam.radius_m.present?
      radius_from_nm = notam.radius_nm.to_f * 1.852 if notam.radius_nm.present?
      [radius_from_m, radius_from_nm, 40.0].compact.max
    end

    def bounds_for_points(points, radius_km)
      latitudes = points.map(&:first)
      longitudes = points.map(&:second)
      center_lat = latitudes.sum / latitudes.size.to_f
      lat_pad = radius_km / 111.0
      lng_pad = radius_km / (111.0 * Math.cos(center_lat * Math::PI / 180)).abs

      {
        lamin: latitudes.min - lat_pad,
        lamax: latitudes.max + lat_pad,
        lomin: longitudes.min - lng_pad,
        lomax: longitudes.max + lng_pad,
      }
    end

    def nearest_point_distance(lat, lng, points)
      points
        .map { |point_lat, point_lng| [[point_lat, point_lng], haversine_km(lat, lng, point_lat, point_lng)] }
        .min_by(&:last)
    end

    def operational_freshness_tier(timestamp, now:, live_window:, recent_window:)
      return if timestamp.blank?

      return "live" if timestamp >= now - live_window
      return "recent" if timestamp >= now - recent_window

      nil
    end

    def operational_relationship_fresh_until(timestamp, freshness_tier:, live_window:, recent_window:)
      window = freshness_tier == "live" ? live_window : recent_window
      timestamp + window
    end

    def freshness_penalty(freshness_tier)
      freshness_tier == "recent" ? 0.12 : 0.0
    end

    def operational_verb(freshness_tier)
      freshness_tier == "recent" ? "recently operated" : "is operating"
    end

    def operational_freshness_label(freshness_tier)
      freshness_tier == "recent" ? "recent" : "live"
    end

    def chokepoint_ship_activity_confidence(ship, distance_km, radius_km, supporting_story, freshness_tier:)
      confidence = 0.52
      confidence += (1.0 - [(distance_km / radius_km), 1.0].min) * 0.2
      confidence += 0.05 if ship.speed.to_f >= 1.0
      confidence += 0.03 if ship.destination.present?
      confidence += 0.05 if supporting_story
      confidence -= freshness_penalty(freshness_tier)
      [confidence, 0.9].min.round(2)
    end

    def submarine_cable_ship_activity_confidence(ship, distance_km, freshness_tier:)
      confidence = 0.58
      confidence += (1.0 - [(distance_km / SHIP_CABLE_DISTANCE_KM), 1.0].min) * 0.22
      confidence += 0.08 if ship.speed.to_f <= 1.0
      confidence -= freshness_penalty(freshness_tier)
      [confidence, 0.93].min.round(2)
    end

    def theater_flight_activity_confidence(flight, distance_km, jamming, notam, freshness_tier:)
      confidence = 0.5
      confidence += (1.0 - [(distance_km / FLIGHT_THEATER_RADIUS_KM), 1.0].min) * 0.16
      confidence += 0.12 if flight.military?
      confidence += 0.1 if emergency_flight?(flight)
      confidence += 0.1 if jamming.present?
      confidence += 0.08 if notam.present?
      confidence -= freshness_penalty(freshness_tier)
      [confidence, 0.95].min.round(2)
    end

    def strategic_air_asset_flight_confidence(flight, distance_km, jamming, notam, freshness_tier:)
      confidence = 0.54
      confidence += (1.0 - [(distance_km / FLIGHT_STRATEGIC_ASSET_RADIUS_KM), 1.0].min) * 0.18
      confidence += 0.12 if flight.military?
      confidence += 0.1 if emergency_flight?(flight)
      confidence += 0.08 if jamming.present?
      confidence += 0.08 if notam.present?
      confidence -= freshness_penalty(freshness_tier)
      [confidence, 0.95].min.round(2)
    end

    def chokepoint_ship_activity_explanation(ship, chokepoint, distance_km, freshness_tier)
      description = "#{asset_label(ship, fallback: ship.mmsi)} #{operational_verb(freshness_tier)} #{distance_km.round}km from #{chokepoint.fetch(:name)}"
      description << " at #{ship.speed.to_f.round(1)}kt" if ship.speed.present?
      description << " toward #{ship.destination}" if ship.destination.present?
      description
    end

    def submarine_cable_ship_activity_explanation(ship, cable, distance_km, freshness_tier)
      description = "#{asset_label(ship, fallback: ship.mmsi)} #{freshness_tier == 'recent' ? 'recently loitered' : 'is loitering'} #{distance_km.round(1)}km from #{cable.name.presence || cable.cable_id}"
      description << " at #{ship.speed.to_f.round(1)}kt" if ship.speed.present?
      description
    end

    def theater_flight_activity_explanation(summary, candidate)
      flight = candidate.fetch(:record)
      description = "#{asset_label(flight, fallback: flight.icao24)} #{operational_verb(candidate.fetch(:freshness_tier))} #{candidate.fetch(:distance_km).round}km from #{summary.fetch(:name)} activity"
      description << ", with military identification" if flight.military?
      description << ", inside #{candidate.dig(:jamming, :percentage).round}% GPS degradation" if candidate[:jamming].present?
      description << ", near #{candidate.dig(:notam, :reason)} airspace restrictions" if candidate[:notam].present?
      description
    end

    def strategic_air_asset_flight_explanation(target, candidate)
      flight = candidate.fetch(:record)
      description = "#{asset_label(flight, fallback: flight.icao24)} #{operational_verb(candidate.fetch(:freshness_tier))} #{candidate.fetch(:distance_km).round}km from #{target.fetch(:entity).canonical_name}"
      description << ", with military identification" if flight.military?
      description << ", near #{candidate.dig(:notam, :reason)} airspace restrictions" if candidate[:notam].present?
      description << ", inside #{candidate.dig(:jamming, :percentage).round}% GPS degradation" if candidate[:jamming].present?
      description
    end

    def ship_operational_evidence_payload(ship, confidence, freshness_tier:)
      {
        evidence: ship,
        evidence_role: "tracked_asset",
        confidence: confidence,
        metadata: {
          "freshness_tier" => freshness_tier,
          "observed_at" => ship.updated_at&.iso8601,
          "speed_knots" => ship.speed&.round(1),
          "heading" => ship.heading&.round(1),
          "destination" => ship.destination,
          "flag" => ship.flag,
          "updated_at" => ship.updated_at&.iso8601,
        }.compact,
      }
    end

    def flight_activity_evidence_payloads(flight, candidate, supporting_clusters)
      payloads = [
        {
          evidence: flight,
          evidence_role: "tracked_asset",
          confidence: candidate.fetch(:confidence),
          metadata: {
            "updated_at" => flight.updated_at&.iso8601,
            "freshness_tier" => candidate.fetch(:freshness_tier),
            "military" => flight.military,
            "squawk" => flight.squawk,
            "origin_country" => flight.origin_country,
            "aircraft_type" => flight.aircraft_type,
          }.compact,
        },
      ]

      if candidate[:jamming].present?
        payloads << {
          evidence: candidate.dig(:jamming, :record),
          evidence_role: "jamming_signal",
          confidence: [0.58 + (candidate.dig(:jamming, :percentage).to_f / 100.0), 0.9].min.round(2),
          metadata: {
            "distance_km" => candidate.dig(:jamming, :distance_km)&.round(1),
            "percentage" => candidate.dig(:jamming, :percentage),
            "level" => candidate.dig(:jamming, :level),
          }.compact,
        }
      end

      if candidate[:notam].present?
        payloads << {
          evidence: candidate.dig(:notam, :record),
          evidence_role: "airspace_notice",
          confidence: 0.72,
          metadata: {
            "distance_km" => candidate.dig(:notam, :distance_km)&.round(1),
            "reason" => candidate.dig(:notam, :reason),
          }.compact,
        }
      end

      payloads +
        supporting_clusters.map do |cluster|
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
    end
  end
end
