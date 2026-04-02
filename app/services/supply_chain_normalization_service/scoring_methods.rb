class SupplyChainNormalizationService
  module ScoringMethods
    private

    def dependency_score_for(import_share_gdp_pct:, top_partner_share_pct:, concentration_hhi:, energy_imports_pct:, buffer_relief:)
      import_intensity = normalized_score(import_share_gdp_pct, ceiling: 6.0)
      top_partner_intensity = normalized_score(top_partner_share_pct, ceiling: 100.0)
      concentration_intensity = normalized_score(concentration_hhi, ceiling: 1.0)
      energy_intensity = normalized_score(energy_imports_pct, ceiling: 100.0)

      score = (import_intensity * 0.45) +
        (top_partner_intensity * 0.2) +
        (concentration_intensity * 0.2) +
        (energy_intensity * 0.15) -
        (buffer_relief.to_f * 0.05)

      score.clamp(0.0, 1.0).round(6)
    end

    def buffer_relief_score(metrics)
      return 0.0 if metrics.blank?

      metrics.filter_map do |metric_key, value|
        next unless metric_key.to_s.match?(/stock|storage|inventory|reserve|cover|buffer/i)
        normalized_score(value, ceiling: 120.0)
      end.max.to_f
    end

    def exposure_contribution_for(dependency_score:, share_fraction:, commodity_key:, chokepoint_key:)
      flow_type = SupplyChainCatalog.commodity_flow_type_for(commodity_key)
      flow_pct = ChokepointMonitorService::CHOKEPOINTS.dig(chokepoint_key.to_sym, :flows, flow_type, :pct)
      chokepoint_importance = 0.55 + (normalized_score(flow_pct, ceiling: 30.0) * 0.45)

      dependency_score.to_f * share_fraction.to_f * chokepoint_importance
    end

    def normalized_score(value, ceiling:)
      return 0.0 if value.blank?

      (value.to_f / ceiling.to_f).clamp(0.0, 1.0)
    end
  end
end
