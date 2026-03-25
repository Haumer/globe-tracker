class OntologyRelationshipSyncService
  DEFAULT_CLUSTER_WINDOW = 72.hours
  DIRECT_STORY_WINDOW = 7.days
  RELATION_DERIVED_BY = "ontology_relationship_sync_v1".freeze
  CHOKEPOINT_ENTITY_TYPE = "corridor".freeze
  THEATER_ENTITY_TYPE = "theater".freeze
  COMMODITY_ENTITY_TYPE = "commodity".freeze
  ASSET_ENTITY_TYPES = {
    airport: "airport",
    military_base: "military_base",
    power_plant: "power_plant",
    submarine_cable: "submarine_cable",
  }.freeze
  CORROBORATED_NEWS_STATUSES = %w[multi_source cross_layer_corroborated].freeze
  THEATER_PRESSURE_TARGETS = {
    "Middle East / Iran War" => %i[hormuz bab_el_mandeb suez],
    "Russia-Ukraine War" => %i[bosphorus danish_straits],
  }.freeze
  COMMODITY_FLOW_TYPES = {
    "OIL_WTI" => :oil,
    "OIL_BRENT" => :oil,
    "LNG" => :lng,
    "GAS_NAT" => :lng,
    "WHEAT" => :grain,
    "COPPER" => :trade,
    "IRON" => :trade,
  }.freeze
  DIRECT_STORY_TERMS = %w[
    shipping ship ships tanker tankers maritime vessel vessels navigation transit
    blockade blocked blocking reopen reopened closure closed lane lanes
    freight cargo oil lng gas energy port ports
  ].freeze
  DOWNSTREAM_ASSET_LIMITS = {
    airport: 4,
    military_base: 4,
    power_plant: 4,
    submarine_cable: 4,
  }.freeze
  OPERATIONAL_ACTIVITY_LIMITS = {
    chokepoint_ship: 6,
    cable_ship: 4,
    theater_flight: 6,
    strategic_air_asset_flight: 3,
  }.freeze
  RECENT_SHIP_WINDOW = 45.minutes
  RECENT_FLIGHT_WINDOW = 45.minutes
  RECENT_JAMMING_WINDOW = 90.minutes
  RECENT_NOTAM_WINDOW = 18.hours
  FLIGHT_THEATER_RADIUS_KM = 250.0
  FLIGHT_STRATEGIC_ASSET_RADIUS_KM = 120.0
  CHOKEPOINT_SHIP_DISTANCE_MIN_KM = 120.0
  CHOKEPOINT_SHIP_DISTANCE_MAX_KM = 280.0
  SHIP_CABLE_DISTANCE_KM = 10.0
  JAMMING_SIGNAL_DISTANCE_KM = 150.0
  OPERATIONAL_NOTAM_REASONS = ["Security", "TFR", "Military", "VIP Movement"].freeze

  class << self
    def sync_recent(window: DEFAULT_CLUSTER_WINDOW, now: Time.current)
      chokepoint_entities = sync_chokepoint_entities
      commodity_entities = sync_relevant_commodity_entities
      theater_since = now - window
      direct_story_since = now - DIRECT_STORY_WINDOW
      theaters = build_active_theaters(since: theater_since)
      corroborated_story_clusters = recent_corroborated_story_clusters(since: direct_story_since)
      theater_entities = theaters.each_with_object({}) do |summary, memo|
        memo[summary.fetch(:name)] = sync_theater_entity(summary)
      end

      {
        theaters: theater_entities.size,
        chokepoints: chokepoint_entities.size,
        commodities: commodity_entities.size,
        theater_pressure: sync_theater_pressure_relationships(
          theaters: theaters,
          theater_entities: theater_entities,
          chokepoint_entities: chokepoint_entities,
          corroborated_story_clusters: corroborated_story_clusters,
          now: now
        ),
        flow_dependencies: sync_flow_dependencies(
          chokepoint_entities: chokepoint_entities,
          commodity_entities: commodity_entities
        ),
        downstream_exposures: sync_downstream_exposure_relationships(
          theaters: theaters,
          theater_entities: theater_entities,
          chokepoint_entities: chokepoint_entities,
          corroborated_story_clusters: corroborated_story_clusters,
          now: now
        ),
        operational_activities: sync_operational_activity_relationships(
          theaters: theaters,
          theater_entities: theater_entities,
          chokepoint_entities: chokepoint_entities,
          corroborated_story_clusters: corroborated_story_clusters,
          now: now
        ),
      }
    end

    alias sync_all sync_recent

    private

    def sync_chokepoint_entities
      ChokepointMonitorService::CHOKEPOINTS.each_with_object({}) do |(key, config), memo|
        entity = OntologySyncSupport.upsert_entity(
          canonical_key: "corridor:chokepoint:#{key}",
          entity_type: CHOKEPOINT_ENTITY_TYPE,
          canonical_name: config.fetch(:name),
          metadata: {
            "strategic_kind" => "chokepoint",
            "description" => config[:description],
            "latitude" => config[:lat],
            "longitude" => config[:lng],
            "radius_km" => config[:radius_km],
            "countries" => config[:countries],
            "flows" => config[:flows],
            "risk_factors" => config[:risk_factors],
          }.compact
        )
        OntologySyncSupport.upsert_alias(entity, config.fetch(:name), alias_type: "official")
        memo[key.to_sym] = entity
      end
    end

    def sync_relevant_commodity_entities
      relevant_symbols = ChokepointMonitorService::RELEVANT_COMMODITY_SYMBOLS.values.flatten.uniq

      CommodityPrice.latest.where(symbol: relevant_symbols).each_with_object({}) do |price, memo|
        entity = OntologySyncSupport.upsert_entity(
          canonical_key: "commodity:#{price.symbol.to_s.downcase}",
          entity_type: COMMODITY_ENTITY_TYPE,
          canonical_name: price.name,
          metadata: {
            "symbol" => price.symbol,
            "category" => price.category,
            "unit" => price.unit,
            "latest_price" => price.price&.to_f,
            "change_pct" => price.change_pct&.to_f,
            "recorded_at" => price.recorded_at&.iso8601,
            "region" => price.region,
          }.compact
        )
        OntologySyncSupport.upsert_alias(entity, price.name, alias_type: "official")
        OntologySyncSupport.upsert_alias(entity, price.symbol, alias_type: "ticker")
        memo[price.symbol] = { entity: entity, price: price }
      end
    end

    def build_active_theaters(since:)
      cluster_summaries = active_conflict_clusters(since: since).map do |cluster|
        { cluster: cluster, summary: cluster_theater_summary(cluster) }
      end

      cluster_summaries.group_by { |payload| payload.dig(:summary, :theater) }.map do |theater_name, payloads|
        clusters = payloads.map { |payload| payload.fetch(:cluster) }
        summary = {
          name: theater_name,
          situation_names: payloads.filter_map { |payload| payload.dig(:summary, :situation_name) }.uniq.sort,
          clusters: prioritized_clusters(clusters),
          cluster_count: clusters.size,
          total_sources: clusters.sum { |cluster| cluster.source_count.to_i },
          max_source_count: clusters.map { |cluster| cluster.source_count.to_i }.max.to_i,
          first_seen_at: clusters.map(&:first_seen_at).compact.min,
          last_seen_at: clusters.map(&:last_seen_at).compact.max,
        }
        summary
      end.sort_by { |summary| [-summary.fetch(:cluster_count), -summary.fetch(:max_source_count), summary.fetch(:name)] }
    end

    def active_conflict_clusters(since:)
      NewsStoryCluster.where(event_family: "conflict")
        .where("last_seen_at >= ?", since)
        .where.not(latitude: nil, longitude: nil)
        .where("source_count >= 2 OR verification_status IN (?)", CORROBORATED_NEWS_STATUSES)
        .order(last_seen_at: :desc)
    end

    def recent_corroborated_story_clusters(since:)
      NewsStoryCluster.where("last_seen_at >= ?", since)
        .where("source_count >= 2 OR verification_status IN (?)", CORROBORATED_NEWS_STATUSES)
        .order(last_seen_at: :desc)
    end

    def cluster_theater_summary(cluster)
      situation_name = ConflictPulseService.infer_situation_name(
        lat: cluster.latitude,
        lng: cluster.longitude,
        text: [cluster.canonical_title, cluster.location_name].compact.join(" ")
      )

      {
        situation_name: situation_name,
        theater: ConflictPulseService.infer_theater(
          lat: cluster.latitude,
          lng: cluster.longitude,
          situation_name: situation_name
        ),
      }
    end

    def prioritized_clusters(clusters)
      clusters.sort_by do |cluster|
        [-cluster.source_count.to_i, -cluster.article_count.to_i, -cluster.cluster_confidence.to_f, -cluster.last_seen_at.to_i]
      end
    end

    def sync_theater_entity(summary)
      OntologySyncSupport.upsert_entity(
        canonical_key: "theater:#{OntologySyncSupport.slugify(summary.fetch(:name))}",
        entity_type: THEATER_ENTITY_TYPE,
        canonical_name: summary.fetch(:name),
        metadata: {
          "cluster_count" => summary.fetch(:cluster_count),
          "total_sources" => summary.fetch(:total_sources),
          "max_source_count" => summary.fetch(:max_source_count),
          "situation_names" => summary.fetch(:situation_names),
          "first_seen_at" => summary.fetch(:first_seen_at)&.iso8601,
          "last_seen_at" => summary.fetch(:last_seen_at)&.iso8601,
        }.compact
      ).tap do |entity|
        OntologySyncSupport.upsert_alias(entity, summary.fetch(:name), alias_type: "official")
      end
    end

    def sync_theater_pressure_relationships(theaters:, theater_entities:, chokepoint_entities:, corroborated_story_clusters:, now:)
      theaters.sum do |summary|
        theater_entity = theater_entities.fetch(summary.fetch(:name))
        target_keys = theater_pressure_target_keys(summary)

        target_keys.count do |chokepoint_key|
          chokepoint_entity = chokepoint_entities[chokepoint_key]
          next false if chokepoint_entity.blank?

          chokepoint = ChokepointMonitorService::CHOKEPOINTS.fetch(chokepoint_key)
          local_clusters = relation_evidence_clusters(summary.fetch(:clusters), chokepoint)
          local_clusters += direct_chokepoint_story_clusters(corroborated_story_clusters, chokepoint_key, chokepoint)
          local_clusters = prioritized_clusters(local_clusters.uniq { |cluster| cluster.id })
          supporting_clusters = supporting_story_clusters(summary.fetch(:clusters), local_clusters)
          relationship = OntologySyncSupport.upsert_relationship(
            source_node: theater_entity,
            target_node: chokepoint_entity,
            relation_type: "theater_pressure",
            confidence: theater_pressure_confidence(summary, local_clusters),
            fresh_until: [summary.fetch(:last_seen_at), now].compact.max + 6.hours,
            derived_by: RELATION_DERIVED_BY,
            explanation: theater_pressure_explanation(summary, chokepoint, local_clusters),
            metadata: {
              "theater" => summary.fetch(:name),
              "situation_names" => summary.fetch(:situation_names),
              "cluster_count" => summary.fetch(:cluster_count),
              "total_sources" => summary.fetch(:total_sources),
              "local_cluster_count" => local_clusters.size,
              "strategic_target" => Array(THEATER_PRESSURE_TARGETS[summary.fetch(:name)]).include?(chokepoint_key),
            }
          )

          sync_relationship_evidences(
            relationship,
            local_clusters.first(2).map do |cluster|
              {
                evidence: cluster,
                evidence_role: "local_story",
                confidence: cluster.cluster_confidence.to_f,
                metadata: { "source_count" => cluster.source_count.to_i, "last_seen_at" => cluster.last_seen_at&.iso8601 },
              }
            end +
            supporting_clusters.first(3).map do |cluster|
              {
                evidence: cluster,
                evidence_role: "supporting_story",
                confidence: cluster.cluster_confidence.to_f,
                metadata: { "source_count" => cluster.source_count.to_i, "last_seen_at" => cluster.last_seen_at&.iso8601 },
              }
            end
          )
          true
        end
      end
    end

    def theater_pressure_target_keys(summary)
      target_keys = Array(THEATER_PRESSURE_TARGETS[summary.fetch(:name)]).dup

      ChokepointMonitorService::CHOKEPOINTS.each do |key, chokepoint|
        target_keys << key if geographically_local_story_clusters(summary.fetch(:clusters), chokepoint).any?
      end

      target_keys.uniq
    end

    def relation_evidence_clusters(clusters, chokepoint)
      clusters.select { |cluster| geographically_local_cluster?(cluster, chokepoint) }
    end

    def direct_chokepoint_story_clusters(clusters, chokepoint_key, chokepoint)
      clusters.select { |cluster| direct_chokepoint_story_cluster?(cluster, chokepoint_key, chokepoint) }
    end

    def geographically_local_story_clusters(clusters, chokepoint)
      clusters.select { |cluster| geographically_local_cluster?(cluster, chokepoint) }
    end

    def supporting_story_clusters(clusters, local_clusters)
      local_ids = local_clusters.map(&:id)
      clusters.reject { |cluster| local_ids.include?(cluster.id) }
    end

    def geographically_local_cluster?(cluster, chokepoint)
      return false if cluster.latitude.blank? || cluster.longitude.blank?

      haversine_km(cluster.latitude, cluster.longitude, chokepoint[:lat], chokepoint[:lng]) <= [chokepoint[:radius_km].to_f * 4.0, 250.0].max
    end

    def cluster_mentions_chokepoint?(cluster, chokepoint_key, chokepoint)
      text = [cluster.canonical_title, cluster.location_name].compact.join(" ").downcase
      chokepoint_terms(chokepoint_key, chokepoint).any? { |term| text.include?(term) }
    end

    def direct_chokepoint_story_cluster?(cluster, chokepoint_key, chokepoint)
      text = [cluster.canonical_title, cluster.location_name].compact.join(" ").downcase
      return false if text.blank?

      mentions_chokepoint = cluster_mentions_chokepoint?(cluster, chokepoint_key, chokepoint)
      return true if geographically_local_cluster?(cluster, chokepoint) && mentions_chokepoint

      mentions_chokepoint && DIRECT_STORY_TERMS.any? { |term| text.include?(term) }
    end

    def chokepoint_terms(chokepoint_key, chokepoint)
      [
        chokepoint.fetch(:name).downcase,
        chokepoint_key.to_s.tr("_", " "),
        OntologySyncSupport.slugify(chokepoint.fetch(:name)).tr("-", " "),
        *chokepoint.fetch(:name).downcase.split(/[^a-z0-9]+/).select { |token| token.length >= 5 },
      ].uniq
    end

    def theater_pressure_confidence(summary, local_clusters)
      confidence = 0.45
      confidence += [summary.fetch(:cluster_count) / 8.0, 0.2].min
      confidence += [summary.fetch(:max_source_count) / 12.0, 0.15].min
      confidence += [local_clusters.size * 0.1, 0.2].min
      [confidence, 0.95].min.round(2)
    end

    def theater_pressure_explanation(summary, chokepoint, local_clusters)
      description = "#{summary.fetch(:name)} is exerting strategic pressure on #{chokepoint.fetch(:name)} from #{summary.fetch(:cluster_count)} recent corroborated conflict story cluster"
      description << "s"

      if local_clusters.any?
        description << ", including #{local_clusters.size} cluster"
        description << "s" unless local_clusters.size == 1
        description << " directly about the chokepoint"
      end

      description
    end

    def sync_flow_dependencies(chokepoint_entities:, commodity_entities:)
      chokepoint_entities.sum do |chokepoint_key, chokepoint_entity|
        ChokepointMonitorService.relevant_commodity_symbols_for(chokepoint_key).count do |symbol|
          commodity_payload = commodity_entities[symbol]
          next false if commodity_payload.blank?

          flow_type = COMMODITY_FLOW_TYPES[symbol] || :trade
          flow = ChokepointMonitorService::CHOKEPOINTS.fetch(chokepoint_key).dig(:flows, flow_type)
          price = commodity_payload.fetch(:price)
          relationship = OntologySyncSupport.upsert_relationship(
            source_node: chokepoint_entity,
            target_node: commodity_payload.fetch(:entity),
            relation_type: "flow_dependency",
            confidence: flow_dependency_confidence(flow, price),
            fresh_until: (price.recorded_at || Time.current) + 2.hours,
            derived_by: RELATION_DERIVED_BY,
            explanation: flow_dependency_explanation(chokepoint_key, flow_type, flow, price),
            metadata: {
              "chokepoint" => chokepoint_key.to_s,
              "commodity_symbol" => symbol,
              "flow_type" => flow_type.to_s,
              "flow_pct" => flow&.dig(:pct),
              "flow_note" => flow&.dig(:note),
              "latest_price" => price.price&.to_f,
              "latest_change_pct" => price.change_pct&.to_f,
              "recorded_at" => price.recorded_at&.iso8601,
            }.compact
          )

          sync_relationship_evidences(
            relationship,
            [
              {
                evidence: price,
                evidence_role: "market_reference",
                confidence: market_signal_confidence(price),
                metadata: {
                  "symbol" => price.symbol,
                  "price" => price.price&.to_f,
                  "change_pct" => price.change_pct&.to_f,
                  "recorded_at" => price.recorded_at&.iso8601,
                }.compact,
              },
            ]
          )
          true
        end
      end
    end

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

    def sync_chokepoint_ship_activity(chokepoint_entities:, corroborated_story_clusters:, now:)
      recent_ships = Ship.where("updated_at >= ?", now - RECENT_SHIP_WINDOW)
        .where.not(latitude: nil, longitude: nil)

      chokepoint_entities.sum do |chokepoint_key, chokepoint_entity|
        chokepoint = ChokepointMonitorService::CHOKEPOINTS.fetch(chokepoint_key)
        radius_km = chokepoint_ship_radius_km(chokepoint)
        lat_range, lng_range = bbox_for_radius(chokepoint[:lat], chokepoint[:lng], radius_km)
        story_evidence = direct_chokepoint_story_clusters(corroborated_story_clusters, chokepoint_key, chokepoint).first(1)

        candidates = recent_ships.where(latitude: lat_range, longitude: lng_range).filter_map do |ship|
          distance = haversine_km(ship.latitude, ship.longitude, chokepoint[:lat], chokepoint[:lng])
          next if distance > radius_km

          {
            record: ship,
            entity: OperationalOntologySyncService.sync_ship(ship),
            distance_km: distance,
            confidence: chokepoint_ship_activity_confidence(ship, distance, radius_km, story_evidence.present?),
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
              fresh_until: ship.updated_at + 90.minutes,
              derived_by: RELATION_DERIVED_BY,
              explanation: chokepoint_ship_activity_explanation(ship, chokepoint, candidate.fetch(:distance_km)),
              metadata: {
                "source_kind" => "ship",
                "target_kind" => "chokepoint",
                "distance_km" => candidate.fetch(:distance_km).round(1),
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
                ship_operational_evidence_payload(ship, candidate.fetch(:confidence)),
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
          confidence: submarine_cable_ship_activity_confidence(ship, closest_cable.fetch(:distance_km)),
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
            fresh_until: ship.updated_at + 75.minutes,
            derived_by: RELATION_DERIVED_BY,
            explanation: submarine_cable_ship_activity_explanation(ship, cable, candidate.fetch(:distance_km)),
            metadata: {
              "source_kind" => "ship",
              "target_kind" => "submarine_cable",
              "distance_km" => candidate.fetch(:distance_km).round(1),
              "speed_knots" => ship.speed&.round(1),
              "flag" => ship.flag,
              "destination" => ship.destination,
            }.compact
          )

          sync_relationship_evidences(
            relationship,
            [
              ship_operational_evidence_payload(ship, candidate.fetch(:confidence)),
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
            fresh_until: flight.updated_at + 90.minutes,
            derived_by: RELATION_DERIVED_BY,
            explanation: theater_flight_activity_explanation(summary, candidate),
            metadata: {
              "source_kind" => "flight",
              "target_kind" => "theater",
              "theater" => summary.fetch(:name),
              "distance_km" => candidate.fetch(:distance_km).round(1),
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
          jamming = nearest_jamming_signal(flight.latitude, flight.longitude, recent_jamming)
          notam = nearest_operational_notam(flight.latitude, flight.longitude, recent_notams)
          next unless heightened_flight_activity?(flight, jamming: jamming, notam: notam)

          distance = haversine_km(flight.latitude, flight.longitude, target.fetch(:latitude), target.fetch(:longitude))
          {
            record: flight,
            entity: OperationalOntologySyncService.sync_flight(flight),
            target: target,
            distance_km: distance,
            jamming: jamming,
            notam: notam,
            confidence: strategic_air_asset_flight_confidence(flight, distance, jamming, notam),
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
              fresh_until: flight.updated_at + 90.minutes,
              derived_by: RELATION_DERIVED_BY,
              explanation: strategic_air_asset_flight_explanation(target, candidate),
              metadata: {
                "source_kind" => "flight",
                "target_kind" => target.fetch(:asset_type).to_s,
                "distance_km" => candidate.fetch(:distance_km).round(1),
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

    def recent_jamming_zones(now:)
      GpsJammingSnapshot.where("recorded_at >= ? AND percentage >= ?", now - RECENT_JAMMING_WINDOW, 10.0)
    end

    def recent_operational_notams(now:)
      Notam.active
        .where(reason: OPERATIONAL_NOTAM_REASONS)
        .where.not(latitude: nil, longitude: nil)
        .where("effective_start >= ? OR fetched_at >= ?", now - RECENT_NOTAM_WINDOW, now - 6.hours)
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

        jamming = nearest_jamming_signal(flight.latitude, flight.longitude, recent_jamming)
        notam = nearest_operational_notam(flight.latitude, flight.longitude, recent_notams)
        next unless heightened_flight_activity?(flight, jamming: jamming, notam: notam)

        {
          record: flight,
          entity: OperationalOntologySyncService.sync_flight(flight),
          distance_km: distance,
          jamming: jamming,
          notam: notam,
          confidence: theater_flight_activity_confidence(flight, distance, jamming, notam),
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

    def chokepoint_ship_activity_confidence(ship, distance_km, radius_km, supporting_story)
      confidence = 0.52
      confidence += (1.0 - [(distance_km / radius_km), 1.0].min) * 0.2
      confidence += 0.05 if ship.speed.to_f >= 1.0
      confidence += 0.03 if ship.destination.present?
      confidence += 0.05 if supporting_story
      [confidence, 0.9].min.round(2)
    end

    def submarine_cable_ship_activity_confidence(ship, distance_km)
      confidence = 0.58
      confidence += (1.0 - [(distance_km / SHIP_CABLE_DISTANCE_KM), 1.0].min) * 0.22
      confidence += 0.08 if ship.speed.to_f <= 1.0
      [confidence, 0.93].min.round(2)
    end

    def theater_flight_activity_confidence(flight, distance_km, jamming, notam)
      confidence = 0.5
      confidence += (1.0 - [(distance_km / FLIGHT_THEATER_RADIUS_KM), 1.0].min) * 0.16
      confidence += 0.12 if flight.military?
      confidence += 0.1 if emergency_flight?(flight)
      confidence += 0.1 if jamming.present?
      confidence += 0.08 if notam.present?
      [confidence, 0.95].min.round(2)
    end

    def strategic_air_asset_flight_confidence(flight, distance_km, jamming, notam)
      confidence = 0.54
      confidence += (1.0 - [(distance_km / FLIGHT_STRATEGIC_ASSET_RADIUS_KM), 1.0].min) * 0.18
      confidence += 0.12 if flight.military?
      confidence += 0.1 if emergency_flight?(flight)
      confidence += 0.08 if jamming.present?
      confidence += 0.08 if notam.present?
      [confidence, 0.95].min.round(2)
    end

    def chokepoint_ship_activity_explanation(ship, chokepoint, distance_km)
      description = "#{asset_label(ship, fallback: ship.mmsi)} is operating #{distance_km.round}km from #{chokepoint.fetch(:name)}"
      description << " at #{ship.speed.to_f.round(1)}kt" if ship.speed.present?
      description << " toward #{ship.destination}" if ship.destination.present?
      description
    end

    def submarine_cable_ship_activity_explanation(ship, cable, distance_km)
      description = "#{asset_label(ship, fallback: ship.mmsi)} is loitering #{distance_km.round(1)}km from #{cable.name.presence || cable.cable_id}"
      description << " at #{ship.speed.to_f.round(1)}kt" if ship.speed.present?
      description
    end

    def theater_flight_activity_explanation(summary, candidate)
      flight = candidate.fetch(:record)
      description = "#{asset_label(flight, fallback: flight.icao24)} is operating #{candidate.fetch(:distance_km).round}km from #{summary.fetch(:name)} activity"
      description << ", with military identification" if flight.military?
      description << ", inside #{candidate.dig(:jamming, :percentage).round}% GPS degradation" if candidate[:jamming].present?
      description << ", near #{candidate.dig(:notam, :reason)} airspace restrictions" if candidate[:notam].present?
      description
    end

    def strategic_air_asset_flight_explanation(target, candidate)
      flight = candidate.fetch(:record)
      description = "#{asset_label(flight, fallback: flight.icao24)} is operating #{candidate.fetch(:distance_km).round}km from #{target.fetch(:entity).canonical_name}"
      description << ", with military identification" if flight.military?
      description << ", near #{candidate.dig(:notam, :reason)} airspace restrictions" if candidate[:notam].present?
      description << ", inside #{candidate.dig(:jamming, :percentage).round}% GPS degradation" if candidate[:jamming].present?
      description
    end

    def ship_operational_evidence_payload(ship, confidence)
      {
        evidence: ship,
        evidence_role: "tracked_asset",
        confidence: confidence,
        metadata: {
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

    def asset_label(record, fallback:)
      record.try(:callsign).presence ||
        record.try(:name).presence ||
        fallback.presence ||
        record.class.name
    end

    def flow_dependency_confidence(flow, price)
      confidence = 0.35
      confidence += [flow&.dig(:pct).to_f / 30.0 * 0.45, 0.45].min if flow&.dig(:pct)
      confidence += [price.change_pct.to_f.abs / 5.0, 0.15].min if price.change_pct.present?
      [confidence, 0.9].min.round(2)
    end

    def market_signal_confidence(price)
      base = 0.55
      base += [price.change_pct.to_f.abs / 10.0, 0.25].min if price.change_pct.present?
      [base, 0.9].min.round(2)
    end

    def flow_dependency_explanation(chokepoint_key, flow_type, flow, price)
      chokepoint_name = ChokepointMonitorService::CHOKEPOINTS.fetch(chokepoint_key).fetch(:name)
      flow_label = {
        oil: "oil",
        lng: "LNG",
        grain: "grain",
        semiconductors: "semiconductors",
        trade: "trade",
        container: "container traffic",
      }.fetch(flow_type.to_sym, flow_type.to_s.tr("_", " "))

      description = +"#{chokepoint_name}"
      if flow&.dig(:pct)
        description << " carries #{flow[:pct]}% of global #{flow_label}"
      else
        description << " is a critical #{flow_label} corridor"
      end
      description << ", making #{price.name} a direct flow dependency benchmark"
      if price.change_pct.present?
        description << " (latest #{price.change_pct.to_f.positive? ? '+' : ''}#{price.change_pct.to_f.round(2)}%)"
      end
      description
    end

    def sync_relationship_evidences(relationship, payloads)
      existing = relationship.ontology_relationship_evidences.index_by do |link|
        [link.evidence_type, link.evidence_id, link.evidence_role]
      end
      desired = {}

      payloads.each do |payload|
        key = [payload.fetch(:evidence).class.name, payload.fetch(:evidence).id, payload.fetch(:evidence_role)]
        desired[key] = payload
        OntologySyncSupport.upsert_relationship_evidence(
          relationship,
          payload.fetch(:evidence),
          evidence_role: payload.fetch(:evidence_role),
          confidence: payload.fetch(:confidence),
          metadata: payload.fetch(:metadata, {})
        )
      end

      stale_ids = existing.reject { |key, _value| desired.key?(key) }.values.map(&:id)
      OntologyRelationshipEvidence.where(id: stale_ids).delete_all if stale_ids.any?
    end

    def haversine_km(lat1, lng1, lat2, lng2)
      radians_per_degree = Math::PI / 180.0
      dlat = (lat2 - lat1) * radians_per_degree
      dlng = (lng2 - lng1) * radians_per_degree
      a = Math.sin(dlat / 2)**2 +
        Math.cos(lat1 * radians_per_degree) *
        Math.cos(lat2 * radians_per_degree) *
        Math.sin(dlng / 2)**2

      6371.0 * (2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a)))
    end
  end
end
