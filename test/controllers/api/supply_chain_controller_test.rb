require "test_helper"

class Api::SupplyChainControllerTest < ActionDispatch::IntegrationTest
  setup do
    CountryCommodityDependency.delete_all
    CountryChokepointExposure.delete_all
    EnergyBalanceSnapshot.delete_all

    CountryCommodityDependency.create!(
      country_code_alpha3: "JPN",
      country_name: "Japan",
      commodity_key: "oil_crude",
      commodity_name: "Crude Oil",
      dependency_score: 0.73,
      import_share_gdp_pct: 3.2
    )

    CountryChokepointExposure.create!(
      country_code_alpha3: "JPN",
      country_name: "Japan",
      commodity_key: "oil_crude",
      commodity_name: "Crude Oil",
      chokepoint_key: "hormuz",
      chokepoint_name: "Strait of Hormuz",
      exposure_score: 0.81,
      dependency_score: 0.73,
      supplier_share_pct: 62.5
    )

    EnergyBalanceSnapshot.create!(
      country_code: "JP",
      country_code_alpha3: "JPN",
      country_name: "Japan",
      commodity_key: "oil_crude",
      metric_key: "stocks_days",
      period_type: "month",
      period_start: Date.new(2026, 3, 1),
      period_end: Date.new(2026, 3, 31),
      value_numeric: 91,
      unit: "days",
      source: "jodi",
      dataset: "oil",
      fetched_at: Time.current
    )
  end

  test "GET /api/supply_chain/dependency_map returns dependency rows" do
    get "/api/supply_chain/dependency_map", params: { chokepoint_key: "hormuz", commodity_key: "oil_crude" }
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal "Strait of Hormuz", data["chokepoint_name"]
    assert_equal "Japan", data.dig("dependency_map", "rows", 0, "country_name")
  end

  test "GET /api/supply_chain/reserve_runway returns runway cards" do
    get "/api/supply_chain/reserve_runway", params: { chokepoint_key: "hormuz", commodity_key: "oil_crude" }
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal 146, data.dig("reserve_runway", "cards", 0, "runway_days")
  end

  test "GET /api/supply_chain/downstream_pathway returns staged narrative" do
    get "/api/supply_chain/downstream_pathway", params: { chokepoint_key: "hormuz", commodity_key: "oil_crude" }
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal "Day 1", data.dig("downstream_pathway", "stages", 0, "phase")
    assert_match(/Hormuz/i, data.dig("downstream_pathway", "summary"))
  end
end
