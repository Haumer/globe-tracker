class OntologyRelationshipSyncService
  module FlowDependencyMethods
    private

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
  end
end
