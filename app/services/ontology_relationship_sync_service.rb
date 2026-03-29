class OntologyRelationshipSyncService
  DEFAULT_CLUSTER_WINDOW = Definitions::DEFAULT_CLUSTER_WINDOW
  DIRECT_STORY_WINDOW = Definitions::DIRECT_STORY_WINDOW
  RELATION_DERIVED_BY = Definitions::RELATION_DERIVED_BY
  CHOKEPOINT_ENTITY_TYPE = Definitions::CHOKEPOINT_ENTITY_TYPE
  THEATER_ENTITY_TYPE = Definitions::THEATER_ENTITY_TYPE
  COMMODITY_ENTITY_TYPE = Definitions::COMMODITY_ENTITY_TYPE
  ASSET_ENTITY_TYPES = Definitions::ASSET_ENTITY_TYPES
  CORROBORATED_NEWS_STATUSES = Definitions::CORROBORATED_NEWS_STATUSES
  THEATER_PRESSURE_TARGETS = Definitions::THEATER_PRESSURE_TARGETS
  COMMODITY_FLOW_TYPES = Definitions::COMMODITY_FLOW_TYPES
  DIRECT_STORY_TERMS = Definitions::DIRECT_STORY_TERMS
  DOWNSTREAM_ASSET_LIMITS = Definitions::DOWNSTREAM_ASSET_LIMITS
  OPERATIONAL_ACTIVITY_LIMITS = Definitions::OPERATIONAL_ACTIVITY_LIMITS
  LIVE_SHIP_WINDOW = Definitions::LIVE_SHIP_WINDOW
  RECENT_SHIP_WINDOW = Definitions::RECENT_SHIP_WINDOW
  LIVE_FLIGHT_WINDOW = Definitions::LIVE_FLIGHT_WINDOW
  RECENT_FLIGHT_WINDOW = Definitions::RECENT_FLIGHT_WINDOW
  LIVE_JAMMING_WINDOW = Definitions::LIVE_JAMMING_WINDOW
  RECENT_JAMMING_WINDOW = Definitions::RECENT_JAMMING_WINDOW
  LIVE_NOTAM_WINDOW = Definitions::LIVE_NOTAM_WINDOW
  RECENT_NOTAM_WINDOW = Definitions::RECENT_NOTAM_WINDOW
  FLIGHT_THEATER_RADIUS_KM = Definitions::FLIGHT_THEATER_RADIUS_KM
  FLIGHT_STRATEGIC_ASSET_RADIUS_KM = Definitions::FLIGHT_STRATEGIC_ASSET_RADIUS_KM
  CHOKEPOINT_SHIP_DISTANCE_MIN_KM = Definitions::CHOKEPOINT_SHIP_DISTANCE_MIN_KM
  CHOKEPOINT_SHIP_DISTANCE_MAX_KM = Definitions::CHOKEPOINT_SHIP_DISTANCE_MAX_KM
  SHIP_CABLE_DISTANCE_KM = Definitions::SHIP_CABLE_DISTANCE_KM
  JAMMING_SIGNAL_DISTANCE_KM = Definitions::JAMMING_SIGNAL_DISTANCE_KM
  OPERATIONAL_NOTAM_REASONS = Definitions::OPERATIONAL_NOTAM_REASONS
  CAMERA_ENTITY_TYPE = Definitions::CAMERA_ENTITY_TYPE
  CAMERA_CORROBORATION_EVENT_TYPES = Definitions::CAMERA_CORROBORATION_EVENT_TYPES
  CAMERA_CORROBORATION_RADIUS_KM = Definitions::CAMERA_CORROBORATION_RADIUS_KM
  CAMERA_CORROBORATION_LIMIT = Definitions::CAMERA_CORROBORATION_LIMIT
  CAMERA_CORROBORATION_WINDOW = Definitions::CAMERA_CORROBORATION_WINDOW
  CAMERA_CORROBORATION_MAX_AGE = Definitions::CAMERA_CORROBORATION_MAX_AGE

  class << self
    include TheaterPressureMethods
    include FlowDependencyMethods
    include DownstreamExposureMethods
    include OperationalActivityMethods
    include LocalCorroborationMethods

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
        local_corroborations: sync_local_corroboration_relationships(now: now),
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

    def asset_label(record, fallback:)
      record.try(:callsign).presence ||
        record.try(:name).presence ||
        fallback.presence ||
        record.class.name
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
