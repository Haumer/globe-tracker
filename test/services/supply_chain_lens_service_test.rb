require "test_helper"

class SupplyChainLensServiceTest < ActiveSupport::TestCase
  setup do
    CountryCommodityDependency.delete_all
    CountryChokepointExposure.delete_all
    EnergyBalanceSnapshot.delete_all

    CountryCommodityDependency.create!(
      country_code_alpha3: "PAK",
      country_name: "Pakistan",
      commodity_key: "oil_crude",
      commodity_name: "Crude Oil",
      dependency_score: 0.68,
      import_share_gdp_pct: 4.1,
      supplier_count: 2,
      metadata: {}
    )

    CountryChokepointExposure.create!(
      country_code_alpha3: "PAK",
      country_name: "Pakistan",
      commodity_key: "oil_crude",
      commodity_name: "Crude Oil",
      chokepoint_key: "hormuz",
      chokepoint_name: "Strait of Hormuz",
      exposure_score: 0.72,
      dependency_score: 0.68,
      supplier_share_pct: 74.0,
      metadata: {}
    )

    EnergyBalanceSnapshot.create!(
      country_code: "PK",
      country_code_alpha3: "PAK",
      country_name: "Pakistan",
      commodity_key: "oil_crude",
      metric_key: "stocks_days",
      period_type: "month",
      period_start: Date.new(2026, 3, 1),
      period_end: Date.new(2026, 3, 31),
      value_numeric: 10,
      unit: "days",
      source: "jodi",
      dataset: "oil",
      fetched_at: Time.current
    )
  end

  test "builds dependency, runway, and pathway slices from observed rows" do
    lens = SupplyChainLensService.call(chokepoint_key: "hormuz", commodity_key: "oil_crude")

    assert_equal "Strait of Hormuz", lens[:chokepoint_name]
    assert_equal "Crude Oil", lens[:commodity_name]
    assert_equal "Pakistan", lens.dig(:dependency_map, :rows, 0, :country_name)
    assert_equal "critical", lens.dig(:dependency_map, :rows, 0, :bucket)
    assert_equal 14, lens.dig(:reserve_runway, :cards, 0, :runway_days)
    assert_equal "critical", lens.dig(:reserve_runway, :cards, 0, :status)
    assert_equal "Day 1", lens.dig(:downstream_pathway, :stages, 0, :phase)
  end
end
