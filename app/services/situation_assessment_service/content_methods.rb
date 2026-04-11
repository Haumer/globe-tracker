class SituationAssessmentService
  module ContentMethods
    private

    def observed_items(relationships:, evidence:)
      relationship_observations = relationships
        .select { |relationship| OBSERVED_RELATIONSHIP_TYPES.include?(relationship[:relation_type].to_s) }
        .filter_map { |relationship| relationship_explanation(relationship) }

      evidence_observations = evidence
        .select { |item| OBSERVED_EVIDENCE_TYPES.include?(item[:type].to_s) }
        .filter_map { |item| evidence_sentence(item) }

      unique_strings(relationship_observations + evidence_observations)
    end

    def reported_items(evidence)
      evidence
        .select { |item| REPORTED_EVIDENCE_TYPES.include?(item[:type].to_s) }
        .filter_map { |item| evidence_sentence(item) }
        .then { |items| unique_strings(items) }
    end

    def inferred_items(relationships)
      relationships
        .select { |relationship| INFERRED_RELATIONSHIP_TYPES.include?(relationship[:relation_type].to_s) }
        .filter_map { |relationship| relationship_explanation(relationship) }
        .then { |items| unique_strings(items) }
    end

    def relationship_explanation(relationship)
      explanation = relationship[:explanation].presence
      return explanation if explanation.present?

      node_name = relationship.dig(:node, :name)
      return if node_name.blank?

      "#{relationship[:relation_type].to_s.tr("_", " ")} relationship with #{node_name}"
    end

    def evidence_sentence(item)
      label = item[:label].presence
      return if label.blank?

      meta = item[:meta].presence
      role = item[:role].presence
      suffix = [role, meta].compact.join(" · ")
      suffix.present? ? "#{label} (#{suffix})" : label
    end

    def missing_data(node:, context:, relationships:, evidence:, observed:, reported:)
      missing = []
      missing << "No active graph relationships attached to this node" if relationships.empty?
      missing << "No direct reporting evidence attached" if reported.empty?
      missing << "No live operational evidence attached" if observed.empty?
      missing << "No geographic coordinates attached to the node" if node[:latitude].blank? || node[:longitude].blank?
      missing << "No actor or affected-entity memberships attached" if node[:node_type] == "event" && Array(context[:memberships]).empty?
      missing << "No evidence links attached to this node" if evidence.empty?
      missing
    end

    def watch_next_for(situation_type:, relationships:)
      relation_types = relationships.map { |relationship| relationship[:relation_type].to_s }.uniq
      watch_next_for_type(situation_type).tap do |items|
        items << "relationship freshness for #{relation_types.join(", ")}" if relation_types.any?
      end
    end

    def watch_next_for_type(situation_type)
      case situation_type
      when "conflict_report", "theater_assessment", "corridor_exposure"
        [
          "new corroborated reporting tied to this node",
          "operational_activity edges from flights, ships, NOTAMs, GPS interference, or outages",
          "fresh downstream_exposure links to infrastructure or commodities",
        ]
      when "infrastructure_disruption", "infrastructure_exposure", "natural_hazard", "infrastructure_asset"
        [
          "new local_corroboration edges from cameras or other ground observations",
          "fresh outage, fire, NOTAM, or transport evidence near exposed assets",
          "new downstream_exposure links from nearby corridors or theaters",
        ]
      when "market_exposure", "supply_chain_exposure"
        [
          "commodity_price evidence moving against recent baselines",
          "new chokepoint_exposure or flow_dependency relationships",
          "fresh reporting that connects market movement to a specific place, actor, or corridor",
        ]
      else
        [
          "new evidence links",
          "new active relationships",
          "changes in confidence, freshness, or relationship type mix",
        ]
      end
    end

    def affected_entities(relationships)
      relationships.map do |relationship|
        {
          relation_type: relationship[:relation_type],
          direction: relationship[:direction],
          confidence: relationship[:confidence],
          node: relationship[:node],
        }.compact
      end
    end

    def summary_for(node:, situation_type:, relationships:, observed:, reported:, inferred:)
      parts = []
      parts << "#{node[:name]} is assessed as #{situation_type.tr("_", " ")}"
      parts << "#{relationships.size} active graph relationship#{relationships.size == 1 ? "" : "s"}"
      parts << "#{reported.size} reporting item#{reported.size == 1 ? "" : "s"}" if reported.any?
      parts << "#{observed.size} observed signal#{observed.size == 1 ? "" : "s"}" if observed.any?
      parts << "#{inferred.size} inferred exposure#{inferred.size == 1 ? "" : "s"}" if inferred.any?
      parts.join("; ")
    end
  end
end
