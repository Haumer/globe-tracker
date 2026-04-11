class SituationAssessmentService
  module ScoringMethods
    private

    def actionable_assessment?(assessment)
      Array(assessment[:observed]).any? ||
        Array(assessment[:reported]).any? ||
        Array(assessment[:relationships]).any? { |relationship| ACTIONABLE_RELATIONSHIP_TYPES.include?(relationship[:relation_type].to_s) }
    end

    def confidence_for(relationships:, evidence:, missing_data:)
      values = relationships.map { |relationship| relationship[:confidence].to_f } +
        evidence.map { |item| item[:confidence].to_f }
      base = values.any? ? (values.sum / values.size) * 100.0 : 30.0
      base -= [missing_data.size * 4, 20].min
      [[base.round, 15].max, 95].min
    end

    def coverage_quality(node:, context:, relationships:, evidence:, observed:, reported:)
      score = 0
      score += 18 if relationships.any?
      score += [relationships.size * 4, 16].min
      score += 18 if evidence.any?
      score += 18 if reported.any?
      score += 18 if observed.any?
      score += 6 if node[:latitude].present? && node[:longitude].present?
      score += 6 if Array(context[:memberships]).any?
      [score, 100].min
    end

    def situation_type_for(node, relationships: [])
      relation_types = relationships.map { |relationship| relationship[:relation_type].to_s }
      return "infrastructure_disruption" if relation_types.include?("infrastructure_disruption")
      return "infrastructure_exposure" if relation_types.include?("infrastructure_exposure")

      if node[:node_type] == "event"
        return event_situation_type(node)
      end

      entity_situation_type(node)
    end

    def event_situation_type(node)
      return "conflict_report" if node[:event_family] == "conflict"
      return "infrastructure_disruption" if node[:event_family] == "infrastructure"
      return "natural_hazard" if %w[disaster weather].include?(node[:event_family].to_s)

      return "#{node[:event_family]}_event" if node[:event_family].present?

      "ontology_context"
    end

    def entity_situation_type(node)
      case node[:entity_type]
      when "theater"
        "theater_assessment"
      when "corridor"
        "corridor_exposure"
      when "commodity"
        "market_exposure"
      when "country", "sector", "input"
        "supply_chain_exposure"
      when "airport", "military_base", "port", "power_plant", "submarine_cable"
        "infrastructure_asset"
      when "asset"
        "operational_asset"
      else
        "ontology_context"
      end
    end

    def unique_evidence(items)
      items.uniq { |item| [item[:type], item[:id], item[:role], item[:label]] }
    end

    def unique_strings(items)
      items.compact_blank.uniq
    end
  end
end
