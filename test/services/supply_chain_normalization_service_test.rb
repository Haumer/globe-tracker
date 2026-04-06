require "test_helper"

class SupplyChainNormalizationServiceTest < ActiveSupport::TestCase
  setup do
    CountryIndicatorSnapshot.delete_all
    CountrySectorSnapshot.delete_all
    TradeFlowSnapshot.delete_all
    EnergyBalanceSnapshot.delete_all
    SectorInputSnapshot.delete_all
    CountryProfile.delete_all
    CountrySectorProfile.delete_all
    SectorInputProfile.delete_all
    CountryCommodityDependency.delete_all
    CountryChokepointExposure.delete_all
    SourceFeedStatus.delete_all

    CountryProfile.create!(
      country_code: "AE",
      country_code_alpha3: "ARE",
      country_name: "United Arab Emirates",
      latest_year: 2024,
      fetched_at: Time.current,
      metadata: {}
    )
    CountryProfile.create!(
      country_code: "SA",
      country_code_alpha3: "SAU",
      country_name: "Saudi Arabia",
      latest_year: 2024,
      fetched_at: Time.current,
      metadata: {}
    )

    create_country_indicator!("gdp_nominal_usd", 4_200_000_000_000)
    create_country_indicator!("gdp_per_capita_usd", 33_950.1)
    create_country_indicator!("population_total", 124_500_000)
    create_country_indicator!("imports_goods_services_pct_gdp", 21.6)
    create_country_indicator!("exports_goods_services_pct_gdp", 22.1)
    create_country_indicator!("energy_imports_net_pct_energy_use", 87.4)

    create_country_sector!("services", "Services", 70.5)
    create_country_sector!("industry", "Industry", 28.4)
    create_country_sector!("manufacturing", "Manufacturing", 19.3)
    create_country_sector!("agriculture", "Agriculture", 1.1)

    TradeFlowSnapshot.create!(
      reporter_country_code: "JP",
      reporter_country_code_alpha3: "JPN",
      reporter_country_name: "Japan",
      partner_country_code: nil,
      partner_country_code_alpha3: "ARE",
      partner_country_name: "United Arab Emirates",
      flow_direction: "import",
      commodity_key: "oil_crude",
      commodity_name: "Crude Oil",
      hs_code: "2709",
      period_type: "month",
      period_start: Date.new(2025, 1, 1),
      period_end: Date.new(2025, 1, 31),
      trade_value_usd: 1_500_000_000,
      quantity: 2_500_000,
      quantity_unit: "tonnes",
      source: "cepii_baci",
      dataset: "baci",
      fetched_at: Time.current
    )
    TradeFlowSnapshot.create!(
      reporter_country_code: "JP",
      reporter_country_code_alpha3: "JPN",
      reporter_country_name: "Japan",
      partner_country_code: nil,
      partner_country_code_alpha3: "SAU",
      partner_country_name: "Saudi Arabia",
      flow_direction: "import",
      commodity_key: "oil_crude",
      commodity_name: "Crude Oil",
      hs_code: "2709",
      period_type: "month",
      period_start: Date.new(2025, 1, 1),
      period_end: Date.new(2025, 1, 31),
      trade_value_usd: 500_000_000,
      quantity: 900_000,
      quantity_unit: "tonnes",
      source: "cepii_baci",
      dataset: "baci",
      fetched_at: Time.current
    )

    SectorInputSnapshot.create!(
      scope_key: "global",
      sector_key: "manufacturing",
      sector_name: "Manufacturing",
      input_kind: "commodity",
      input_key: "helium",
      input_name: "Helium",
      coefficient: 0.42,
      period_year: 2024,
      source: "oecd",
      dataset: "icio",
      fetched_at: Time.current
    )
    SectorInputSnapshot.create!(
      scope_key: "global",
      sector_key: "manufacturing",
      sector_name: "Manufacturing",
      input_kind: "commodity",
      input_key: "semiconductor_equipment",
      input_name: "Semiconductor Equipment",
      coefficient: 0.18,
      period_year: 2024,
      source: "oecd",
      dataset: "icio",
      fetched_at: Time.current
    )

    EnergyBalanceSnapshot.create!(
      country_code: "JP",
      country_code_alpha3: "JPN",
      country_name: "Japan",
      commodity_key: "oil_crude",
      metric_key: "stocks_days",
      period_type: "month",
      period_start: Date.new(2025, 1, 1),
      period_end: Date.new(2025, 1, 31),
      value_numeric: 92,
      unit: "days",
      source: "jodi",
      dataset: "oil",
      fetched_at: Time.current
    )
  end

  test "builds normalized profiles, dependencies, and chokepoint exposures" do
    count = SupplyChainNormalizationService.new.refresh

    assert_operator count, :>=, 8
    assert_equal 1, CountryProfile.count
    assert_equal 4, CountrySectorProfile.count
    assert_equal 2, SectorInputProfile.count
    assert_operator CountryCommodityDependency.count, :>=, 1

    profile = CountryProfile.find_by!(country_code_alpha3: "JPN")
    assert_equal 2024, profile.latest_year
    assert_in_delta 87.4, profile.energy_imports_net_pct_energy_use.to_f, 0.001
    assert_equal "services", profile.metadata.fetch("top_sectors").first.fetch("sector_key")

    manufacturing = CountrySectorProfile.find_by!(country_code_alpha3: "JPN", sector_key: "manufacturing")
    assert_equal 3, manufacturing.rank
    assert_in_delta 19.3, manufacturing.share_pct.to_f, 0.001

    helium = SectorInputProfile.find_by!(scope_key: "global", sector_key: "manufacturing", input_key: "helium")
    assert_equal 1, helium.rank
    assert_in_delta 0.42, helium.coefficient.to_f, 0.001

    dependency = CountryCommodityDependency.find_by!(country_code_alpha3: "JPN", commodity_key: "oil_crude")
    assert_equal 2, dependency.supplier_count
    assert_equal "ARE", dependency.top_partner_country_code_alpha3
    assert_in_delta 75.0, dependency.top_partner_share_pct.to_f, 0.001
    assert_in_delta 0.625, dependency.concentration_hhi.to_f, 0.001
    assert_operator dependency.dependency_score.to_f, :>, 0.15
    assert_equal 2, dependency.metadata.fetch("partner_breakdown").size

    hormuz = CountryChokepointExposure.find_by!(country_code_alpha3: "JPN", commodity_key: "oil_crude", chokepoint_key: "hormuz")
    malacca = CountryChokepointExposure.find_by!(country_code_alpha3: "JPN", commodity_key: "oil_crude", chokepoint_key: "malacca")

    assert_in_delta 100.0, hormuz.supplier_share_pct.to_f, 0.001
    assert_operator hormuz.exposure_score.to_f, :>, 0.05
    assert_includes hormuz.rationale, "Strait of Hormuz"

    assert_operator malacca.exposure_score.to_f, :>, 0.01
    assert_includes malacca.rationale, "Strait of Malacca"
    assert_equal ["ARE", "SAU"], malacca.metadata.fetch("supporting_partner_codes")

    status = SourceFeedStatus.find_by(feed_key: "derived_supply_chain:supply-chain-derivations")
    assert_equal "success", status.status
    assert_equal CountryChokepointExposure.count, status.metadata.fetch("country_chokepoint_exposures")
  end

  test "seeds estimated dependencies and chokepoint exposures when trade feeds are empty" do
    TradeFlowSnapshot.delete_all
    SectorInputSnapshot.delete_all

    count = SupplyChainNormalizationService.new.refresh

    assert_operator count, :>=, 8
    assert_operator SectorInputProfile.count, :>=, 2

    estimated_dependency = CountryCommodityDependency.find_by!(country_code_alpha3: "JPN", commodity_key: "oil_crude")
    assert_equal "estimate", estimated_dependency.period_type
    assert_equal true, estimated_dependency.metadata.fetch("estimated")
    assert_includes estimated_dependency.metadata.fetch("route_priors"), "malacca"

    estimated_exposure = CountryChokepointExposure.find_by!(country_code_alpha3: "JPN", commodity_key: "oil_crude", chokepoint_key: "hormuz")
    assert_equal true, estimated_exposure.metadata.fetch("estimated")
    assert_includes estimated_exposure.rationale, "Estimated"

    baseline_input = SectorInputProfile.find_by!(scope_key: "global", sector_key: "manufacturing", input_key: "oil_refined")
    assert_equal true, baseline_input.metadata.fetch("estimated")
    assert_equal "curated_prior", baseline_input.metadata.fetch("source")
  end

  private

  def create_country_indicator!(indicator_key, value)
    CountryIndicatorSnapshot.create!(
      country_code: "JP",
      country_code_alpha3: "JPN",
      country_name: "Japan",
      indicator_key: indicator_key,
      indicator_name: indicator_key.humanize,
      period_type: "year",
      period_start: Date.new(2024, 1, 1),
      period_end: Date.new(2024, 12, 31),
      value_numeric: value,
      unit: "n/a",
      source: "world_bank",
      dataset: "wdi",
      series_key: indicator_key,
      fetched_at: Time.current
    )
  end

  def create_country_sector!(sector_key, sector_name, value)
    CountrySectorSnapshot.create!(
      country_code: "JP",
      country_code_alpha3: "JPN",
      country_name: "Japan",
      sector_key: sector_key,
      sector_name: sector_name,
      metric_key: "gdp_share_pct",
      metric_name: "GDP Share",
      period_year: 2024,
      value_numeric: value,
      unit: "%",
      source: "world_bank",
      dataset: "wdi",
      fetched_at: Time.current
    )
  end
end
