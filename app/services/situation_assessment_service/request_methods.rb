class SituationAssessmentService
  module RequestMethods
    private

    def recent_requests(limit:)
      requests = recent_event_requests(limit: limit) + recent_relationship_node_requests(limit: limit)
      requests.uniq { |request| [request[:kind], request[:id]] }.first(limit * 8)
    end

    def recent_event_requests(limit:)
      OntologyEvent
        .where("last_seen_at >= ?", @now - RECENT_WINDOW)
        .order(last_seen_at: :desc, updated_at: :desc)
        .limit(limit * 3)
        .filter_map { |event| request_for_node(event) }
    end

    def recent_relationship_node_requests(limit:)
      OntologyRelationship.active
        .includes(:source_node, :target_node)
        .order(confidence: :desc, updated_at: :desc)
        .limit(limit * 10)
        .flat_map { |relationship| [relationship.target_node, relationship.source_node] }
        .filter_map { |node| request_for_node(node) }
    end

    def request_for_node(node)
      case node
      when OntologyEntity
        return if EXCLUDED_RECENT_ENTITY_TYPES.include?(node.entity_type)

        { kind: "entity", id: node.canonical_key }
      when OntologyEvent
        request_for_event(node)
      end
    end

    def request_for_event(event)
      key = event.canonical_key.to_s
      if key.start_with?("news-story-cluster:")
        return { kind: "news_story_cluster", id: key.delete_prefix("news-story-cluster:") }
      end

      { kind: "event", id: key }
    end
  end
end
