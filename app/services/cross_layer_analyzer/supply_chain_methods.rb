class CrossLayerAnalyzer
  module SupplyChainMethods
    private

    def supply_chain_vulnerabilities
      sector_rows_by_country = CountrySectorProfile
        .where(sector_key: %w[manufacturing industry agriculture])
        .order(country_code_alpha3: :asc, rank: :asc)
        .to_a
        .group_by(&:country_code_alpha3)
      dependency_rows_by_country = CountryCommodityDependency
        .order(dependency_score: :desc)
        .to_a
        .group_by(&:country_code_alpha3)
      input_rows_by_sector = SectorInputProfile
        .where(scope_key: "global")
        .order(:sector_key, :rank)
        .to_a
        .group_by(&:sector_key)
      detected_at = Time.current.iso8601

      CountryProfile.where.not(country_code: nil).where.not(energy_imports_net_pct_energy_use: nil).filter_map do |profile|
        driver_sector = supply_chain_driver_sector(Array(sector_rows_by_country[profile.country_code_alpha3]))
        next if driver_sector.blank?

        dependencies = Array(dependency_rows_by_country[profile.country_code_alpha3]).first(3)
        modeled_inputs = dependencies.any? ? [] : Array(input_rows_by_sector[driver_sector.sector_key]).first(3)

        vulnerability_score = supply_chain_vulnerability_score(
          profile: profile,
          driver_sector: driver_sector,
          dependencies: dependencies
        )
        next if vulnerability_score < 0.56

        primary_dependency = dependencies.first
        primary_input = modeled_inputs.first
        dependency_label = primary_dependency&.commodity_name || primary_input&.input_name
        country_lat, country_lng = COUNTRY_CENTROIDS[profile.country_code]

        {
          type: "supply_chain_vulnerability",
          severity: supply_chain_vulnerability_severity(profile: profile, driver_sector: driver_sector, vulnerability_score: vulnerability_score),
          title: supply_chain_vulnerability_title(profile: profile, driver_sector: driver_sector, dependency_label: dependency_label),
          description: supply_chain_vulnerability_description(
            profile: profile,
            driver_sector: driver_sector,
            dependencies: dependencies,
            modeled_inputs: modeled_inputs
          ),
          lat: country_lat,
          lng: country_lng,
          entities: supply_chain_vulnerability_entities(
            profile: profile,
            driver_sector: driver_sector,
            dependencies: dependencies,
            modeled_inputs: modeled_inputs,
            primary_dependency: primary_dependency,
            primary_input: primary_input
          ),
          detected_at: detected_at,
        }
      end
        .sort_by { |insight| -supply_chain_severity_score(insight[:severity], insight.dig(:entities, :dependencies, 0, :dependency_score)) }
        .first(6)
    rescue => e
      Rails.logger.error("CrossLayerAnalyzer supply_chain_vulnerabilities: #{e.message}")
      []
    end

    def country_chokepoint_dependencies
      profiles_by_country = CountryProfile.where.not(country_code_alpha3: nil).index_by(&:country_code_alpha3)
      chokepoint_statuses = monitored_chokepoints_by_key
      detected_at = Time.current.iso8601

      CountryChokepointExposure
        .order(exposure_score: :desc)
        .to_a
        .group_by(&:country_code_alpha3)
        .filter_map do |country_alpha3, exposures|
          top_exposures = exposures.sort_by { |row| -row.exposure_score.to_f }.first(3)
          primary_exposure = top_exposures.first
          next if primary_exposure.blank? || primary_exposure.exposure_score.to_f < 0.28

          profile = profiles_by_country[country_alpha3]
          country_code = profile&.country_code || primary_exposure.country_code
          country_lat, country_lng = COUNTRY_CENTROIDS[country_code]
          status_label = chokepoint_statuses.dig(primary_exposure.chokepoint_key.to_s, :status) || "structural"

          {
            type: "country_chokepoint_dependency",
            severity: supply_chain_chokepoint_severity(
              exposure_score: primary_exposure.exposure_score.to_f,
              chokepoint_status: status_label
            ),
            title: country_chokepoint_dependency_title(primary_exposure, top_exposures),
            description: country_chokepoint_dependency_description(
              primary_exposure: primary_exposure,
              profile: profile,
              top_exposures: top_exposures,
              status_label: status_label
            ),
            lat: country_lat,
            lng: country_lng,
            entities: country_chokepoint_dependency_entities(
              country_alpha3: country_alpha3,
              country_code: country_code,
              primary_exposure: primary_exposure,
              status_label: status_label,
              top_exposures: top_exposures
            ),
            detected_at: detected_at,
          }
        end
        .sort_by { |insight| -supply_chain_severity_score(insight[:severity], insight.dig(:entities, :exposures, 0, :exposure_score)) }
        .first(6)
    rescue => e
      Rails.logger.error("CrossLayerAnalyzer country_chokepoint_dependencies: #{e.message}")
      []
    end

    def supply_chain_vulnerability_entities(profile:, driver_sector:, dependencies:, modeled_inputs:, primary_dependency:, primary_input:)
      secondary_node = if primary_dependency.present?
        {
          kind: "commodity",
          id: "commodity:#{primary_dependency.commodity_key}",
          label: primary_dependency.commodity_name,
        }
      elsif primary_input&.input_kind == "commodity"
        {
          kind: "commodity",
          id: "commodity:#{primary_input.input_key}",
          label: primary_input.input_name,
        }
      end

      {
        country: {
          code: profile.country_code,
          alpha3: profile.country_code_alpha3,
          name: profile.country_name,
        },
        primary_node: {
          kind: "entity",
          id: "country:#{profile.country_code_alpha3.to_s.downcase}",
          label: profile.country_name,
        },
        secondary_node: secondary_node,
        sectors: [{
          key: driver_sector.sector_key,
          name: driver_sector.sector_name,
          share_pct: driver_sector.share_pct.to_f.round(1),
        }],
        dependencies: dependencies.map do |dependency|
          {
            commodity_key: dependency.commodity_key,
            commodity_name: dependency.commodity_name,
            dependency_score: dependency.dependency_score.to_f.round(2),
            estimated: dependency.metadata["estimated"] == true,
          }
        end,
        modeled_inputs: modeled_inputs.map do |input|
          {
            input_key: input.input_key,
            input_name: input.input_name,
            coefficient: input.coefficient.to_f.round(2),
            estimated: input.metadata["estimated"] == true,
          }
        end,
      }.compact
    end

    def supply_chain_vulnerability_title(profile:, driver_sector:, dependency_label:)
      if dependency_label.present?
        "#{profile.country_name}: #{driver_sector.sector_name.downcase} base vulnerable to #{dependency_label.downcase} shocks"
      else
        "#{profile.country_name}: import-heavy #{driver_sector.sector_name.downcase} base vulnerable to supply shocks"
      end
    end

    def supply_chain_vulnerability_description(profile:, driver_sector:, dependencies:, modeled_inputs:)
      description_parts = [
        "#{profile.energy_imports_net_pct_energy_use.to_f.round(1)}% net energy imports",
        "#{driver_sector.sector_name} #{driver_sector.share_pct.to_f.round(1)}% of GDP",
      ]

      if dependencies.any?
        labels = dependencies.map do |dependency|
          dependency.metadata["estimated"] ? "#{dependency.commodity_name} (estimated)" : dependency.commodity_name
        end
        description_parts << "tracked dependencies: #{labels.join(', ')}"
      elsif modeled_inputs.any?
        description_parts << "modeled inputs: #{modeled_inputs.map(&:input_name).join(', ')}"
      end

      description_parts.join(" · ")
    end

    def supply_chain_vulnerability_severity(profile:, driver_sector:, vulnerability_score:)
      if vulnerability_score >= 0.78 || (profile.energy_imports_net_pct_energy_use.to_f >= 75 && driver_sector.share_pct.to_f >= 18)
        "high"
      else
        "medium"
      end
    end

    def country_chokepoint_dependency_entities(country_alpha3:, country_code:, primary_exposure:, status_label:, top_exposures:)
      {
        country: {
          code: country_code,
          alpha3: country_alpha3,
          name: primary_exposure.country_name,
        },
        primary_node: {
          kind: "entity",
          id: "country:#{country_alpha3.to_s.downcase}",
          label: primary_exposure.country_name,
        },
        secondary_node: {
          kind: "commodity",
          id: "commodity:#{primary_exposure.commodity_key}",
          label: primary_exposure.commodity_name,
        },
        chokepoint: {
          name: primary_exposure.chokepoint_name,
          status: status_label,
        },
        exposures: top_exposures.map do |exposure|
          {
            chokepoint_name: exposure.chokepoint_name,
            commodity_name: exposure.commodity_name,
            exposure_score: exposure.exposure_score.to_f.round(2),
            estimated: exposure.metadata["estimated"] == true,
          }
        end,
      }
    end

    def country_chokepoint_dependency_title(primary_exposure, top_exposures)
      if top_exposures.second&.chokepoint_name.present? && top_exposures.second.chokepoint_name != primary_exposure.chokepoint_name
        "#{primary_exposure.country_name}: #{primary_exposure.commodity_name} chain runs through #{primary_exposure.chokepoint_name} and #{top_exposures.second.chokepoint_name}"
      else
        "#{primary_exposure.country_name}: #{primary_exposure.chokepoint_name} sits on its #{primary_exposure.commodity_name.to_s.downcase} chain"
      end
    end

    def country_chokepoint_dependency_description(primary_exposure:, profile:, top_exposures:, status_label:)
      description_parts = [
        "#{primary_exposure.commodity_name} exposure score #{primary_exposure.exposure_score.to_f.round(2)}",
        "#{primary_exposure.chokepoint_name} status #{status_label}",
      ]
      if profile&.energy_imports_net_pct_energy_use.present?
        description_parts << "#{profile.energy_imports_net_pct_energy_use.to_f.round(1)}% net energy imports"
      end
      description_parts << "derived from macro route priors" if top_exposures.all? { |row| row.metadata["estimated"] }
      description_parts.join(" · ")
    end

    def supply_chain_driver_sector(sector_rows)
      manufacturing = Array(sector_rows).find { |row| row.sector_key == "manufacturing" && row.share_pct.to_f >= 12.0 }
      return manufacturing if manufacturing

      industry = Array(sector_rows).find { |row| row.sector_key == "industry" && row.share_pct.to_f >= 18.0 }
      return industry if industry

      Array(sector_rows).find { |row| row.sector_key == "agriculture" && row.share_pct.to_f >= 8.0 }
    end

    def supply_chain_vulnerability_score(profile:, driver_sector:, dependencies:)
      energy_intensity = (profile.energy_imports_net_pct_energy_use.to_f / 100.0).clamp(0.0, 1.0)
      trade_intensity = (profile.imports_goods_services_pct_gdp.to_f / 60.0).clamp(0.0, 1.0)
      sector_intensity = (driver_sector.share_pct.to_f / 30.0).clamp(0.0, 1.0)
      dependency_intensity = Array(dependencies).first(2).map { |row| row.dependency_score.to_f }.max.to_f

      ((energy_intensity * 0.45) +
        (trade_intensity * 0.15) +
        (sector_intensity * 0.2) +
        (dependency_intensity * 0.2))
        .clamp(0.0, 1.0)
    end

    def supply_chain_chokepoint_severity(exposure_score:, chokepoint_status:)
      case chokepoint_status.to_s
      when "critical"
        exposure_score >= 0.35 ? "critical" : "high"
      when "elevated"
        exposure_score >= 0.4 ? "high" : "medium"
      else
        exposure_score >= 0.6 ? "high" : "medium"
      end
    end

    def supply_chain_severity_score(severity, value)
      (severity_score(severity) * 10) + value.to_f
    end

    def monitored_chokepoints_by_key
      @monitored_chokepoints_by_key ||= Array(ChokepointMonitorService.analyze).index_by { |row| row[:id].to_s }
    rescue => e
      Rails.logger.warn("CrossLayerAnalyzer monitored_chokepoints_by_key: #{e.message}")
      {}
    end
  end
end
