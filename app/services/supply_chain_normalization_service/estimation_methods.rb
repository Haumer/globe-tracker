class SupplyChainNormalizationService
  module EstimationMethods
    private

    def build_baseline_sector_input_profiles(country_sector_profiles, now)
      latest_period_year = country_sector_profiles.filter_map { |row| row[:period_year] }.max || now.year
      sector_names = country_sector_profiles
        .group_by { |row| row.fetch(:sector_key) }
        .transform_values { |rows| rows.max_by { |row| row.fetch(:share_pct).to_f }.fetch(:sector_name) }

      sector_names.each_with_object([]) do |(sector_key, sector_name), records|
        SupplyChainCatalog.baseline_sector_inputs_for(sector_key).each_with_index do |prior, index|
          records << {
            scope_key: "global",
            country_code: nil,
            country_code_alpha3: nil,
            country_name: nil,
            sector_key: sector_key,
            sector_name: sector_name,
            input_kind: prior.fetch(:input_kind),
            input_key: prior.fetch(:input_key),
            input_name: prior.fetch(:input_name),
            period_year: latest_period_year,
            coefficient: prior.fetch(:coefficient),
            rank: index + 1,
            metadata: {
              "source" => "curated_prior",
              "dataset" => "supply_chain_catalog",
              "estimated" => true,
              "note" => prior[:note],
            }.compact,
            fetched_at: now,
            created_at: now,
            updated_at: now,
          }
        end
      end
    end

    def build_estimated_country_commodity_dependencies(country_profiles:, country_sector_profiles:, existing_keys:, now:)
      country_lookup = country_profiles.index_by { |row| row.fetch(:country_code_alpha3) }
      sector_rows_by_country = country_sector_profiles.group_by { |row| row.fetch(:country_code_alpha3) }
      dependency_rows = []

      SupplyChainCatalog::CHOKEPOINT_ROUTE_PRIORS.each do |prior|
        Array(prior[:destination_country_alpha3]).each do |country_alpha3|
          country = country_lookup[country_alpha3]
          next if country.blank?

          Array(prior[:commodity_keys]).each do |commodity_key|
            next unless SupplyChainCatalog.energy_commodity?(commodity_key)
            next if existing_keys.include?([country_alpha3, commodity_key])

            driver_sector = driver_sector_for_country(
              sector_rows: Array(sector_rows_by_country[country_alpha3]),
              commodity_key: commodity_key
            )
            dependency_score = estimated_dependency_score(
              country_profile: country,
              driver_sector: driver_sector
            )
            next if dependency_score < 0.3

            dependency_rows << {
              country_code: country.fetch(:country_code),
              country_code_alpha3: country_alpha3,
              country_name: country.fetch(:country_name),
              commodity_key: commodity_key,
              commodity_name: SupplyChainCatalog.commodity_name_for(commodity_key),
              period_start: Date.new(now.year, 1, 1),
              period_end: Date.new(now.year, 12, 31),
              period_type: "estimate",
              import_value_usd: nil,
              supplier_count: nil,
              top_partner_country_code: nil,
              top_partner_country_code_alpha3: nil,
              top_partner_country_name: nil,
              top_partner_share_pct: nil,
              concentration_hhi: nil,
              import_share_gdp_pct: nil,
              dependency_score: dependency_score,
              metadata: {
                "estimated" => true,
                "derivation" => "macro_route_prior",
                "energy_imports_pct" => country[:energy_imports_net_pct_energy_use]&.to_f,
                "imports_goods_services_pct_gdp" => country[:imports_goods_services_pct_gdp]&.to_f,
                "driver_sector_key" => driver_sector&.dig(:sector_key),
                "driver_sector_name" => driver_sector&.dig(:sector_name),
                "driver_sector_share_pct" => driver_sector&.dig(:share_pct)&.to_f,
                "route_priors" => SupplyChainCatalog.route_priors_for(
                  country_code_alpha3: country_alpha3,
                  commodity_key: commodity_key
                ).map { |item| item.fetch(:chokepoint_key).to_s },
              }.compact,
              fetched_at: now,
              created_at: now,
              updated_at: now,
            }
          end
        end
      end

      dependency_rows.uniq { |row| [row.fetch(:country_code_alpha3), row.fetch(:commodity_key)] }
    end

    def driver_sector_for_country(sector_rows:, commodity_key:)
      target_sector_keys = SupplyChainCatalog.energy_commodity?(commodity_key) ? %w[manufacturing industry] : %w[manufacturing]

      Array(sector_rows)
        .select { |row| target_sector_keys.include?(row.fetch(:sector_key)) }
        .max_by { |row| row.fetch(:share_pct).to_f }
    end

    def estimated_dependency_score(country_profile:, driver_sector:)
      energy_intensity = normalized_score(country_profile[:energy_imports_net_pct_energy_use], ceiling: 100.0)
      trade_intensity = normalized_score(country_profile[:imports_goods_services_pct_gdp], ceiling: 60.0)
      sector_intensity = normalized_score(driver_sector&.dig(:share_pct), ceiling: 35.0)

      ((energy_intensity * 0.6) + (trade_intensity * 0.2) + (sector_intensity * 0.2))
        .then { |score| score * 0.78 }
        .clamp(0.0, 1.0)
        .round(6)
    end
  end
end
