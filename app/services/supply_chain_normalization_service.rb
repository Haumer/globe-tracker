require "set"

class SupplyChainNormalizationService
  extend Refreshable

  SOURCE_STATUS = {
    provider: "derived_supply_chain",
    display_name: "Supply Chain Derivations",
    feed_kind: "derived_supply_chain",
    endpoint_url: nil,
  }.freeze

  MAX_SECTOR_INPUTS_PER_SCOPE = 8
  MAX_CHOKEPOINT_EXPOSURES_PER_COMMODITY = 4

  refreshes model: CountryProfile, interval: 12.hours, column: :fetched_at

  def refresh
    now = Time.current

    country_profiles = build_country_profiles(now)
    country_sector_profiles = build_country_sector_profiles(now)
    enrich_country_profiles!(country_profiles, country_sector_profiles)

    sector_input_profiles = build_sector_input_profiles(now)
    country_commodity_dependencies, partner_support = build_country_commodity_dependencies(country_profiles, now)
    country_chokepoint_exposures = build_country_chokepoint_exposures(
      country_commodity_dependencies: country_commodity_dependencies,
      partner_support: partner_support,
      now: now
    )

    persist_profiles!(
      country_profiles: country_profiles,
      country_sector_profiles: country_sector_profiles,
      sector_input_profiles: sector_input_profiles,
      country_commodity_dependencies: country_commodity_dependencies,
      country_chokepoint_exposures: country_chokepoint_exposures
    )

    total_records = country_profiles.size +
      country_sector_profiles.size +
      sector_input_profiles.size +
      country_commodity_dependencies.size +
      country_chokepoint_exposures.size

    SourceFeedStatusRecorder.record(
      **SOURCE_STATUS,
      status: "success",
      records_fetched: raw_record_count,
      records_stored: total_records,
      metadata: {
        country_profiles: country_profiles.size,
        country_sector_profiles: country_sector_profiles.size,
        sector_input_profiles: sector_input_profiles.size,
        country_commodity_dependencies: country_commodity_dependencies.size,
        country_chokepoint_exposures: country_chokepoint_exposures.size,
      },
      occurred_at: now
    )

    total_records
  rescue StandardError => e
    SourceFeedStatusRecorder.record(
      **SOURCE_STATUS,
      status: "error",
      error_message: e.message,
      occurred_at: Time.current
    )
    Rails.logger.error("SupplyChainNormalizationService: #{e.message}")
    0
  end

  private

  def raw_record_count
    CountryIndicatorSnapshot.count +
      CountrySectorSnapshot.count +
      SectorInputSnapshot.count +
      TradeFlowSnapshot.count +
      EnergyBalanceSnapshot.count
  end

  def build_country_profiles(now)
    latest_indicators_by_country.values.map do |rows_by_indicator|
      representative = rows_by_indicator.values.first
      next if representative.blank?

      {
        country_code: representative.country_code,
        country_code_alpha3: representative.country_code_alpha3,
        country_name: representative.country_name,
        latest_year: rows_by_indicator.values.filter_map { |row| row.period_start&.year }.max,
        gdp_nominal_usd: value_numeric(rows_by_indicator["gdp_nominal_usd"]),
        gdp_per_capita_usd: value_numeric(rows_by_indicator["gdp_per_capita_usd"]),
        population_total: value_numeric(rows_by_indicator["population_total"]),
        imports_goods_services_pct_gdp: value_numeric(rows_by_indicator["imports_goods_services_pct_gdp"]),
        exports_goods_services_pct_gdp: value_numeric(rows_by_indicator["exports_goods_services_pct_gdp"]),
        energy_imports_net_pct_energy_use: value_numeric(rows_by_indicator["energy_imports_net_pct_energy_use"]),
        metadata: {
          "indicator_periods" => rows_by_indicator.transform_values { |row| row.period_start&.year },
          "indicator_series" => rows_by_indicator.transform_values(&:series_key),
        },
        fetched_at: now,
        created_at: now,
        updated_at: now,
      }
    end.compact.sort_by { |row| row.fetch(:country_name) }
  end

  def build_country_sector_profiles(now)
    records = []

    latest_country_sector_rows.values.group_by(&:country_code_alpha3).each_value do |rows|
      ranked_rows = rows.sort_by { |row| -row.value_numeric.to_f }

      ranked_rows.each_with_index do |row, index|
        records << {
          country_code: row.country_code,
          country_code_alpha3: row.country_code_alpha3,
          country_name: row.country_name,
          sector_key: row.sector_key,
          sector_name: row.sector_name,
          period_year: row.period_year,
          share_pct: row.value_numeric,
          rank: index + 1,
          metadata: {
            "metric_key" => row.metric_key,
            "metric_name" => row.metric_name,
            "source" => row.source,
            "dataset" => row.dataset,
          },
          fetched_at: now,
          created_at: now,
          updated_at: now,
        }
      end
    end

    records
  end

  def enrich_country_profiles!(country_profiles, country_sector_profiles)
    sectors_by_country = country_sector_profiles.group_by { |row| row.fetch(:country_code_alpha3) }

    country_profiles.each do |profile|
      top_sectors = Array(sectors_by_country[profile.fetch(:country_code_alpha3)]).sort_by { |row| row.fetch(:rank) }.first(4)
      profile[:metadata] = profile.fetch(:metadata).merge(
        "top_sectors" => top_sectors.map do |row|
          {
            "sector_key" => row.fetch(:sector_key),
            "sector_name" => row.fetch(:sector_name),
            "share_pct" => row.fetch(:share_pct).to_f.round(2),
            "rank" => row.fetch(:rank),
          }
        end
      )
    end
  end

  def build_sector_input_profiles(now)
    records = []

    latest_sector_input_rows.values
      .group_by { |row| [row.scope_key, row.country_code_alpha3, row.sector_key] }
      .each_value do |rows|
        rows.sort_by { |row| -row.coefficient.to_f }
          .first(MAX_SECTOR_INPUTS_PER_SCOPE)
          .each_with_index do |row, index|
            records << {
              scope_key: row.scope_key,
              country_code: row.country_code,
              country_code_alpha3: row.country_code_alpha3,
              country_name: row.country_name,
              sector_key: row.sector_key,
              sector_name: row.sector_name,
              input_kind: row.input_kind,
              input_key: row.input_key,
              input_name: row.input_name.presence || row.input_key.to_s.humanize,
              period_year: row.period_year,
              coefficient: row.coefficient,
              rank: index + 1,
              metadata: {
                "source" => row.source,
                "dataset" => row.dataset,
              },
              fetched_at: now,
              created_at: now,
              updated_at: now,
            }
          end
      end

    records
  end

  def build_country_commodity_dependencies(country_profiles, now)
    country_lookup = country_profiles.index_by { |row| row.fetch(:country_code_alpha3) }
    latest_energy_metrics = latest_energy_metrics_by_country_commodity
    dependencies = []
    partner_support = {}

    latest_import_trade_groups.each do |(country_alpha3, commodity_key), flows|
      next if country_alpha3.blank? || commodity_key.blank?

      country = country_lookup[country_alpha3]
      representative = flows.first
      total_import_value = flows.sum { |flow| flow.trade_value_usd.to_d }
      next if total_import_value <= 0

      partners = aggregate_partners(flows: flows, total_import_value: total_import_value)
      top_partner = partners.first
      country_gdp = country&.fetch(:gdp_nominal_usd, nil)
      country_gdp = country_gdp.present? ? country_gdp.to_d : 0.to_d
      import_share_gdp_pct = country_gdp.positive? ? ((total_import_value / country_gdp) * 100) : nil
      concentration_hhi = partners.sum { |partner| partner.fetch(:share_fraction)**2 }
      energy_metrics = latest_energy_metrics[[country_alpha3, commodity_key]] || {}
      buffer_relief = buffer_relief_score(energy_metrics)
      dependency_score = dependency_score_for(
        import_share_gdp_pct: import_share_gdp_pct,
        top_partner_share_pct: top_partner&.fetch(:share_pct, 0),
        concentration_hhi: concentration_hhi,
        energy_imports_pct: country&.fetch(:energy_imports_net_pct_energy_use, nil),
        buffer_relief: buffer_relief
      )

      record = {
        country_code: country&.fetch(:country_code, nil) || representative.reporter_country_code,
        country_code_alpha3: country_alpha3,
        country_name: country&.fetch(:country_name, nil) || representative.reporter_country_name || country_alpha3,
        commodity_key: commodity_key,
        commodity_name: representative.commodity_name.presence || SupplyChainCatalog.commodity_name_for(commodity_key),
        period_start: flows.map(&:period_start).compact.min,
        period_end: flows.map(&:period_end).compact.max,
        period_type: representative.period_type,
        import_value_usd: total_import_value,
        supplier_count: partners.size,
        top_partner_country_code: top_partner&.fetch(:partner_country_code, nil),
        top_partner_country_code_alpha3: top_partner&.fetch(:partner_country_code_alpha3, nil),
        top_partner_country_name: top_partner&.fetch(:partner_country_name, nil),
        top_partner_share_pct: top_partner&.fetch(:share_pct, nil),
        concentration_hhi: concentration_hhi.round(6),
        import_share_gdp_pct: import_share_gdp_pct&.round(6),
        dependency_score: dependency_score,
        metadata: {
          "partner_breakdown" => partners.first(5).map do |partner|
            {
              "country_code" => partner[:partner_country_code],
              "country_code_alpha3" => partner[:partner_country_code_alpha3],
              "country_name" => partner[:partner_country_name],
              "share_pct" => partner[:share_pct].round(2),
              "trade_value_usd" => partner[:trade_value_usd].to_f.round(2),
            }
          end,
          "energy_metrics" => energy_metrics.transform_values { |value| value.to_f.round(4) },
          "buffer_relief_score" => buffer_relief,
        },
        fetched_at: now,
        created_at: now,
        updated_at: now,
      }

      dependencies << record
      partner_support[[country_alpha3, commodity_key]] = {
        dependency: record,
        partners: partners,
      }
    end

    [dependencies, partner_support]
  end

  def build_country_chokepoint_exposures(country_commodity_dependencies:, partner_support:, now:)
    exposure_map = {}

    country_commodity_dependencies.each do |dependency|
      country_alpha3 = dependency.fetch(:country_code_alpha3)
      commodity_key = dependency.fetch(:commodity_key)
      support = partner_support[[country_alpha3, commodity_key]]
      next if support.blank?

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

      apply_route_priors!(
        exposure_map: exposure_map,
        dependency: dependency,
        support: support
      )
    end

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

      supporting_share_pct = supporting_rows.sum { |row| row.fetch(:supplier_share_pct).to_f }
      supporting_partner_names = supporting_rows.flat_map { |row| row.fetch(:metadata).fetch("supporting_partner_names", []) }.uniq
      supporting_partner_codes = supporting_rows.flat_map { |row| row.fetch(:metadata).fetch("supporting_partner_codes", []) }.uniq

      register_exposure!(
        exposure_map: exposure_map,
        dependency: dependency,
        chokepoint_key: prior.fetch(:chokepoint_key),
        score_contribution: [supporting_score * prior.fetch(:multiplier).to_f, dependency.fetch(:dependency_score).to_f].min,
        supplier_share_pct: supporting_share_pct,
        partner_names: supporting_partner_names,
        partner_codes: supporting_partner_codes,
        rationale: prior.fetch(:note),
        metadata: {
          "support_type" => "route_prior",
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

  def persist_profiles!(country_profiles:, country_sector_profiles:, sector_input_profiles:, country_commodity_dependencies:, country_chokepoint_exposures:)
    ActiveRecord::Base.transaction do
      CountryProfile.delete_all
      CountrySectorProfile.delete_all
      SectorInputProfile.delete_all
      CountryCommodityDependency.delete_all
      CountryChokepointExposure.delete_all

      CountryProfile.insert_all!(country_profiles) if country_profiles.any?
      CountrySectorProfile.insert_all!(country_sector_profiles) if country_sector_profiles.any?
      SectorInputProfile.insert_all!(sector_input_profiles) if sector_input_profiles.any?
      CountryCommodityDependency.insert_all!(country_commodity_dependencies) if country_commodity_dependencies.any?
      CountryChokepointExposure.insert_all!(country_chokepoint_exposures) if country_chokepoint_exposures.any?
    end
  end

  def latest_indicators_by_country
    @latest_indicators_by_country ||= CountryIndicatorSnapshot
      .order(country_code_alpha3: :asc, indicator_key: :asc, period_start: :desc, fetched_at: :desc)
      .to_a
      .group_by { |row| [row.country_code_alpha3, row.indicator_key] }
      .transform_values(&:first)
      .each_with_object(Hash.new { |hash, key| hash[key] = {} }) do |((_country_code_alpha3, indicator_key), row), memo|
        memo[row.country_code_alpha3][indicator_key] = row
      end
  end

  def latest_country_sector_rows
    @latest_country_sector_rows ||= CountrySectorSnapshot
      .where(metric_key: "gdp_share_pct")
      .order(country_code_alpha3: :asc, sector_key: :asc, period_year: :desc, fetched_at: :desc)
      .to_a
      .group_by { |row| [row.country_code_alpha3, row.sector_key] }
      .transform_values(&:first)
  end

  def latest_sector_input_rows
    @latest_sector_input_rows ||= SectorInputSnapshot
      .order(scope_key: :asc, sector_key: :asc, input_kind: :asc, input_key: :asc, period_year: :desc, fetched_at: :desc)
      .to_a
      .group_by { |row| [row.scope_key, row.sector_key, row.input_kind, row.input_key] }
      .transform_values(&:first)
  end

  def latest_import_trade_groups
    @latest_import_trade_groups ||= begin
      grouped = TradeFlowSnapshot.where(flow_direction: "import")
        .where.not(trade_value_usd: nil)
        .order(reporter_country_code_alpha3: :asc, commodity_key: :asc, period_start: :desc, fetched_at: :desc)
        .to_a
        .group_by { |row| [row.reporter_country_code_alpha3, row.commodity_key] }

      grouped.transform_values do |rows|
        latest_period_start = rows.filter_map(&:period_start).max
        rows.select { |row| row.period_start == latest_period_start }
      end
    end
  end

  def latest_energy_metrics_by_country_commodity
    @latest_energy_metrics_by_country_commodity ||= EnergyBalanceSnapshot
      .order(country_code_alpha3: :asc, commodity_key: :asc, metric_key: :asc, period_start: :desc, fetched_at: :desc)
      .to_a
      .group_by { |row| [row.country_code_alpha3, row.commodity_key, row.metric_key] }
      .transform_values(&:first)
      .each_with_object(Hash.new { |hash, key| hash[key] = {} }) do |((_country_alpha3, commodity_key, metric_key), row), memo|
        memo[[row.country_code_alpha3, commodity_key]][metric_key] = row.value_numeric.to_f
      end
  end

  def aggregate_partners(flows:, total_import_value:)
    flows.group_by { |flow| [flow.partner_country_code_alpha3, flow.partner_country_code, flow.partner_country_name] }
      .map do |(partner_alpha3, partner_alpha2, partner_name), rows|
        partner_value = rows.sum { |row| row.trade_value_usd.to_d }
        share_fraction = total_import_value.positive? ? (partner_value / total_import_value) : 0.to_d

        {
          partner_country_code: partner_alpha2,
          partner_country_code_alpha3: partner_alpha3,
          partner_country_name: partner_name.presence || partner_alpha3,
          trade_value_usd: partner_value,
          share_fraction: share_fraction.to_f,
          share_pct: (share_fraction * 100).to_f,
        }
      end
      .sort_by { |partner| -partner.fetch(:trade_value_usd) }
  end

  def direct_chokepoints_for_partner(partner)
    country_code = partner.fetch(:partner_country_code, nil).to_s.upcase
    return [] if country_code.blank?

    ChokepointMonitorService::CHOKEPOINTS.each_with_object([]) do |(chokepoint_key, config), memo|
      memo << chokepoint_key.to_s if Array(config[:countries]).include?(country_code)
    end
  end

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

  def value_numeric(row)
    row&.value_numeric
  end

  def chokepoint_name_for(chokepoint_key)
    ChokepointMonitorService::CHOKEPOINTS.fetch(chokepoint_key.to_sym).fetch(:name)
  end
end
