class ShippingLaneMapService
  include AnchorMethods
  include PortSelectionMethods
  include PresentationMethods
  include RouteMethods

  MAX_LANES = 80
  MAX_EXPOSURES_PER_LANE = 4
  STRATEGIC_CORRIDOR_COUNTRIES = %w[USA CAN BRA AUS].freeze

  SyntheticDependency = Struct.new(
    :country_code,
    :country_code_alpha3,
    :country_name,
    :commodity_key,
    :commodity_name,
    :dependency_score,
    :metadata,
    :import_value_usd,
    :import_share_gdp_pct,
    :top_partner_share_pct,
    :supplier_count,
    :top_partner_country_code,
    :top_partner_country_code_alpha3,
    :top_partner_country_name,
    keyword_init: true
  )

  SyntheticExposure = Struct.new(
    :country_code,
    :country_code_alpha3,
    :country_name,
    :commodity_key,
    :commodity_name,
    :chokepoint_key,
    :chokepoint_name,
    :exposure_score,
    :dependency_score,
    :supplier_share_pct,
    :metadata,
    :rationale,
    keyword_init: true
  )

  class << self
    def lanes(limit: MAX_LANES)
      new(limit: limit).lanes
    end

    def corridors
      CorridorGraph.baseline_corridors
    end
  end

  def initialize(limit:)
    @limit = limit
  end

  def lanes
    dependency_lanes = grouped_exposures.filter_map do |(country_alpha3, commodity_key), exposures|
      build_lane(
        dependency: dependencies[[country_alpha3, commodity_key]],
        exposures: exposures
      )
    end

    strategic_lanes = build_strategic_gap_lanes(existing_lane_ids: dependency_lanes.map { |lane| lane[:id] })

    (dependency_lanes + strategic_lanes)
      .sort_by { |lane| lane_sort_key(lane) }
      .first(@limit)
  end

  private

  def lane_sort_key(lane)
    [-lane.fetch(:vulnerability_score).to_f, -lane.fetch(:exposure_score).to_f, lane.fetch(:name)]
  end

  def grouped_exposures
    @grouped_exposures ||= CountryChokepointExposure
      .order(exposure_score: :desc, dependency_score: :desc)
      .to_a
      .group_by { |row| [row.country_code_alpha3, row.commodity_key] }
  end

  def dependencies
    @dependencies ||= CountryCommodityDependency
      .order(dependency_score: :desc)
      .index_by { |row| [row.country_code_alpha3, row.commodity_key] }
  end

  def country_profiles_by_alpha3
    @country_profiles_by_alpha3 ||= CountryProfile.all.index_by(&:country_code_alpha3)
  end

  def country_sector_profiles_by_alpha3
    @country_sector_profiles_by_alpha3 ||= CountrySectorProfile
      .order(country_code_alpha3: :asc, share_pct: :desc)
      .to_a
      .group_by(&:country_code_alpha3)
  end

  def trade_locations_by_country
    @trade_locations_by_country ||= TradeLocation.active
      .where(location_kind: "port")
      .order(:country_code, :name)
      .group_by(&:country_code)
  end

  def trade_locations_by_locode
    @trade_locations_by_locode ||= TradeLocation.active.index_by { |location| location.locode.to_s.upcase }
  end

  def build_strategic_gap_lanes(existing_lane_ids:)
    strategic_gap_specs.filter_map do |spec|
      next if existing_lane_ids.include?(spec[:id])

      build_lane(
        dependency: spec.fetch(:dependency),
        exposures: spec.fetch(:exposures)
      )
    end
  end

  def strategic_gap_specs
    specs = []
    seen = {}

    STRATEGIC_CORRIDOR_COUNTRIES.each do |country_alpha3|
      profile = country_profiles_by_alpha3[country_alpha3]
      next if profile.blank?

      candidate_priors = SupplyChainCatalog::CHOKEPOINT_ROUTE_PRIORS.select do |prior|
        Array(prior[:destination_country_alpha3]).include?(country_alpha3)
      end
      next if candidate_priors.blank?

      strategic_priority_commodities_for(country_alpha3).each do |commodity_key|
        next if dependencies.key?([country_alpha3, commodity_key])

        prior = strategic_route_prior_for(
          country_code_alpha3: country_alpha3,
          commodity_key: commodity_key,
          priors: candidate_priors
        )
        next if prior.blank?

        dependency_score = strategic_dependency_score_for(profile: profile, commodity_key: commodity_key)
        next if dependency_score < 0.24

        id = "#{country_alpha3.downcase}-#{commodity_key}"
        next if seen[id]
        seen[id] = true

        dependency = SyntheticDependency.new(
          country_code: profile.country_code,
          country_code_alpha3: country_alpha3,
          country_name: profile.country_name,
          commodity_key: commodity_key,
          commodity_name: SupplyChainCatalog.commodity_name_for(commodity_key),
          dependency_score: dependency_score.round(6),
          metadata: {
            "estimated" => true,
            "strategic_corridor" => true,
            "route_priors" => [prior.fetch(:chokepoint_key).to_s],
          }
        )

        exposures = Array(prior[:requires_any_source_chokepoint]).map do |required_key|
          synthetic_exposure_for(
            dependency: dependency,
            chokepoint_key: required_key,
            exposure_score: [dependency_score * 0.42, dependency_score].min,
            rationale: "Strategic corridor support via #{required_key.to_s.humanize}."
          )
        end
        exposures << synthetic_exposure_for(
          dependency: dependency,
          chokepoint_key: prior.fetch(:chokepoint_key),
          exposure_score: [dependency_score * prior.fetch(:multiplier).to_f, dependency_score].min,
          rationale: prior.fetch(:note)
        )

        specs << {
          id: id,
          dependency: dependency,
          exposures: exposures.compact,
        }
      end
    end

    specs
  end

  def strategic_route_prior_for(country_code_alpha3:, commodity_key:, priors:)
    filtered = Array(priors).select { |prior| Array(prior[:commodity_keys]).include?(commodity_key.to_s) }
    return if filtered.blank?

    return filtered.find { |prior| prior[:chokepoint_key].to_s == "panama" } if %w[USA].include?(country_code_alpha3)
    return filtered.find { |prior| prior[:chokepoint_key].to_s == "hormuz" } if %w[CAN BRA].include?(country_code_alpha3)
    return filtered.find { |prior| prior[:chokepoint_key].to_s == "malacca" } if %w[AUS].include?(country_code_alpha3)

    filtered.max_by { |prior| prior.fetch(:shipping_priority, 0) }
  end

  def strategic_priority_commodities_for(country_alpha3)
    case country_alpha3
    when "USA" then %w[lng oil_refined]
    when "CAN", "BRA" then %w[oil_crude lng]
    when "AUS" then %w[lng oil_refined]
    else %w[lng oil_refined]
    end
  end

  def strategic_dependency_score_for(profile:, commodity_key:)
    trade_score = (profile.imports_goods_services_pct_gdp.to_f / 60.0).clamp(0.0, 1.0)
    export_score = (profile.exports_goods_services_pct_gdp.to_f / 60.0).clamp(0.0, 1.0)
    sector_score = country_sector_weight(profile.country_code_alpha3, commodity_key: commodity_key)

    ((trade_score * 0.4) + (export_score * 0.35) + (sector_score * 0.25)).clamp(0.0, 1.0)
  end

  def country_sector_weight(country_alpha3, commodity_key:)
    rows = Array(country_sector_profiles_by_alpha3[country_alpha3])
    target_sector_keys = SupplyChainCatalog.energy_commodity?(commodity_key) ? %w[manufacturing industry] : %w[manufacturing]
    strongest = rows.select { |row| target_sector_keys.include?(row.sector_key) }.max_by(&:share_pct)
    return 0.0 if strongest.blank?

    (strongest.share_pct.to_f / 35.0).clamp(0.0, 1.0)
  end

  def synthetic_exposure_for(dependency:, chokepoint_key:, exposure_score:, rationale:)
    config = ChokepointMonitorService::CHOKEPOINTS[chokepoint_key.to_sym]
    return if config.blank?

    SyntheticExposure.new(
      country_code: dependency.country_code,
      country_code_alpha3: dependency.country_code_alpha3,
      country_name: dependency.country_name,
      commodity_key: dependency.commodity_key,
      commodity_name: dependency.commodity_name,
      chokepoint_key: chokepoint_key.to_s,
      chokepoint_name: config.fetch(:name),
      exposure_score: exposure_score.round(6),
      dependency_score: dependency.dependency_score.to_f.round(6),
      supplier_share_pct: 0.0,
      metadata: {
        "estimated" => true,
        "support_types" => ["strategic_corridor"],
      },
      rationale: rationale
    )
  end
end
