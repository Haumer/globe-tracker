class SupplyChainNormalizationService
  module ExposureMethods
    private

    def build_country_chokepoint_exposures(country_commodity_dependencies:, partner_support:, now:)
      exposure_map = {}

      country_commodity_dependencies.each do |dependency|
        country_alpha3 = dependency.fetch(:country_code_alpha3)
        commodity_key = dependency.fetch(:commodity_key)
        support = partner_support[[country_alpha3, commodity_key]]

        if support.present?
          register_direct_supplier_exposures!(
            exposure_map: exposure_map,
            dependency: dependency,
            support: support,
            commodity_key: commodity_key
          )
          apply_route_priors!(exposure_map: exposure_map, dependency: dependency, support: support)
        elsif dependency.dig(:metadata, "estimated")
          apply_estimated_route_priors!(exposure_map: exposure_map, dependency: dependency)
        end
      end

      finalized_exposures(exposure_map, now: now)
    end

    def register_direct_supplier_exposures!(exposure_map:, dependency:, support:, commodity_key:)
      support.fetch(:partners).each do |partner|
        next if partner.fetch(:share_fraction) <= 0

        direct_chokepoints_for_partner(partner).each do |chokepoint_key|
          register_exposure!(
            exposure_map: exposure_map,
            dependency: dependency,
            chokepoint_key: chokepoint_key,
            score_contribution: exposure_contribution_for(
              dependency_score: dependency.fetch(:dependency_score),
              share_fraction: partner.fetch(:share_fraction),
              commodity_key: commodity_key,
              chokepoint_key: chokepoint_key
            ),
            supplier_share_pct: partner.fetch(:share_pct),
            partner_names: [partner.fetch(:partner_country_name)],
            partner_codes: [partner.fetch(:partner_country_code_alpha3)],
            rationale: "#{partner.fetch(:partner_country_name)} exports commonly transit #{chokepoint_name_for(chokepoint_key)}.",
            metadata: {
              "support_type" => "direct_supplier",
            }
          )
        end
      end
    end

    def finalized_exposures(exposure_map, now:)
      exposure_map.values
        .group_by { |row| [row.fetch(:country_code_alpha3), row.fetch(:commodity_key)] }
        .flat_map do |_key, rows|
          rows.sort_by { |row| -row.fetch(:exposure_score).to_f }
            .first(MAX_CHOKEPOINT_EXPOSURES_PER_COMMODITY)
        end
        .map do |row|
          row.merge(
            exposure_score: row.fetch(:exposure_score).to_f.clamp(0.0, 1.0).round(6),
            supplier_share_pct: row.fetch(:supplier_share_pct).to_f.clamp(0.0, 100.0).round(4),
            metadata: row.fetch(:metadata).merge(
              "supporting_partner_names" => row.fetch(:metadata).fetch("supporting_partner_names", []).uniq.sort,
              "supporting_partner_codes" => row.fetch(:metadata).fetch("supporting_partner_codes", []).uniq.sort,
            ),
            fetched_at: now,
            created_at: now,
            updated_at: now,
          )
        end
    end

    def apply_route_priors!(exposure_map:, dependency:, support:)
      priors = SupplyChainCatalog.route_priors_for(
        country_code_alpha3: dependency.fetch(:country_code_alpha3),
        commodity_key: dependency.fetch(:commodity_key)
      )
      return if priors.blank?

      priors.each do |prior|
        required_keys = Array(prior[:requires_any_source_chokepoint]).map(&:to_s)
        supporting_rows = required_keys.filter_map do |chokepoint_key|
          exposure_map[[dependency.fetch(:country_code_alpha3), dependency.fetch(:commodity_key), chokepoint_key]]
        end
        next if supporting_rows.blank?

        supporting_score = supporting_rows.sum { |row| row.fetch(:exposure_score).to_f }
        next if supporting_score <= 0

        register_exposure!(
          exposure_map: exposure_map,
          dependency: dependency,
          chokepoint_key: prior.fetch(:chokepoint_key),
          score_contribution: [supporting_score * prior.fetch(:multiplier).to_f, dependency.fetch(:dependency_score).to_f].min,
          supplier_share_pct: supporting_rows.sum { |row| row.fetch(:supplier_share_pct).to_f },
          partner_names: supporting_rows.flat_map { |row| row.fetch(:metadata).fetch("supporting_partner_names", []) }.uniq,
          partner_codes: supporting_rows.flat_map { |row| row.fetch(:metadata).fetch("supporting_partner_codes", []) }.uniq,
          rationale: prior.fetch(:note),
          metadata: {
            "support_type" => "route_prior",
            "requires_any_source_chokepoint" => required_keys,
          }
        )
      end
    end

    def apply_estimated_route_priors!(exposure_map:, dependency:)
      priors = SupplyChainCatalog.route_priors_for(
        country_code_alpha3: dependency.fetch(:country_code_alpha3),
        commodity_key: dependency.fetch(:commodity_key)
      )
      return if priors.blank?

      priors.each do |prior|
        required_keys = Array(prior[:requires_any_source_chokepoint]).map(&:to_s)

        required_keys.each do |required_key|
          register_exposure!(
            exposure_map: exposure_map,
            dependency: dependency,
            chokepoint_key: required_key,
            score_contribution: [dependency.fetch(:dependency_score).to_f * 0.52, dependency.fetch(:dependency_score).to_f].min,
            supplier_share_pct: 0.0,
            partner_names: [],
            partner_codes: [],
            rationale: "Estimated from #{dependency.fetch(:country_name)} macro energy dependence and modeled route exposure via #{chokepoint_name_for(required_key)}.",
            metadata: {
              "support_type" => "estimated_macro_prior",
              "estimated" => true,
              "requires_route_prior" => prior.fetch(:chokepoint_key).to_s,
            }
          )
        end

        register_exposure!(
          exposure_map: exposure_map,
          dependency: dependency,
          chokepoint_key: prior.fetch(:chokepoint_key),
          score_contribution: [dependency.fetch(:dependency_score).to_f * prior.fetch(:multiplier).to_f * 0.85, dependency.fetch(:dependency_score).to_f].min,
          supplier_share_pct: 0.0,
          partner_names: [],
          partner_codes: [],
          rationale: "Estimated from #{dependency.fetch(:country_name)} macro energy dependence and #{prior.fetch(:note)}",
          metadata: {
            "support_type" => "estimated_route_prior",
            "estimated" => true,
            "requires_any_source_chokepoint" => required_keys,
          }
        )
      end
    end

    def register_exposure!(exposure_map:, dependency:, chokepoint_key:, score_contribution:, supplier_share_pct:, partner_names:, partner_codes:, rationale:, metadata:)
      return if chokepoint_key.blank? || score_contribution.to_f <= 0

      key = [dependency.fetch(:country_code_alpha3), dependency.fetch(:commodity_key), chokepoint_key.to_s]
      existing = exposure_map[key] ||= {
        country_code: dependency.fetch(:country_code),
        country_code_alpha3: dependency.fetch(:country_code_alpha3),
        country_name: dependency.fetch(:country_name),
        commodity_key: dependency.fetch(:commodity_key),
        commodity_name: dependency.fetch(:commodity_name),
        chokepoint_key: chokepoint_key.to_s,
        chokepoint_name: chokepoint_name_for(chokepoint_key),
        exposure_score: 0.0,
        dependency_score: dependency.fetch(:dependency_score).to_f,
        supplier_share_pct: 0.0,
        rationale: nil,
        metadata: {
          "supporting_partner_names" => [],
          "supporting_partner_codes" => [],
          "support_types" => [],
        },
      }

      existing[:exposure_score] += score_contribution.to_f
      existing[:supplier_share_pct] += supplier_share_pct.to_f
      existing[:dependency_score] = [existing[:dependency_score].to_f, dependency.fetch(:dependency_score).to_f].max
      existing[:metadata]["supporting_partner_names"] |= Array(partner_names).compact_blank
      existing[:metadata]["supporting_partner_codes"] |= Array(partner_codes).compact_blank
      existing[:metadata]["support_types"] |= [metadata["support_type"]].compact
      metadata.each do |meta_key, meta_value|
        next if meta_key == "support_type"
        existing[:metadata][meta_key] = meta_value
      end
      existing[:rationale] = [existing[:rationale], rationale].compact.join(" ").strip
    end

    def direct_chokepoints_for_partner(partner)
      country_code = partner.fetch(:partner_country_code, nil).to_s.upcase
      return [] if country_code.blank?

      ChokepointMonitorService::CHOKEPOINTS.each_with_object([]) do |(chokepoint_key, config), memo|
        memo << chokepoint_key.to_s if Array(config[:countries]).include?(country_code)
      end
    end

    def chokepoint_name_for(chokepoint_key)
      ChokepointMonitorService::CHOKEPOINTS.fetch(chokepoint_key.to_sym).fetch(:name)
    end
  end
end
