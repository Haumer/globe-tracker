class OntologyRelationshipSyncService
  module TheaterPressureMethods
    private

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
  end
end
