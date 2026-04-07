require "test_helper"

class Api::ChokepointsControllerTest < ActionDispatch::IntegrationTest
  test "GET /api/chokepoints returns persisted chokepoints" do
    LayerSnapshot.create!(
      snapshot_type: "chokepoints",
      scope_key: "global",
      payload: {
        chokepoints: [
          { id: "hormuz", name: "Strait of Hormuz", status: "monitoring" },
        ],
      },
      status: "ready",
      fetched_at: Time.current,
      expires_at: 15.minutes.from_now,
    )

    get "/api/chokepoints"
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal 1, data["count"]
    assert_equal "ready", data["snapshot_status"]
    assert_equal "Strait of Hormuz", data["chokepoints"].first["name"]
  end

  test "GET /api/chokepoints/:id returns supply chain lens payload" do
    LayerSnapshot.create!(
      snapshot_type: "chokepoints",
      scope_key: "global",
      payload: {
        chokepoints: [
          {
            id: "hormuz",
            name: "Strait of Hormuz",
            status: "elevated",
            lat: 26.56,
            lng: 56.27,
            flows: {
              oil: { pct: 21, volume: "20.5M barrels/day" },
            },
          },
        ],
      },
      status: "ready",
      fetched_at: Time.current,
      expires_at: 15.minutes.from_now,
    )

    CountryCommodityDependency.create!(
      country_code_alpha3: "IND",
      country_name: "India",
      commodity_key: "oil_crude",
      commodity_name: "Crude Oil",
      dependency_score: 0.61,
      import_share_gdp_pct: 2.4
    )

    CountryChokepointExposure.create!(
      country_code_alpha3: "IND",
      country_name: "India",
      commodity_key: "oil_crude",
      commodity_name: "Crude Oil",
      chokepoint_key: "hormuz",
      chokepoint_name: "Strait of Hormuz",
      exposure_score: 0.67,
      supplier_share_pct: 54.2
    )

    EnergyBalanceSnapshot.create!(
      country_code: "IN",
      country_code_alpha3: "IND",
      country_name: "India",
      commodity_key: "oil_crude",
      metric_key: "stocks_days",
      period_type: "month",
      period_start: Date.new(2026, 3, 1),
      period_end: Date.new(2026, 3, 31),
      value_numeric: 22,
      unit: "days",
      source: "jodi",
      dataset: "oil",
      fetched_at: Time.current
    )

    get "/api/chokepoints/hormuz"
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal "oil_crude", data.dig("chokepoint", "primary_commodity_key")
    assert_equal "India", data.dig("chokepoint", "supply_chain_lens", "dependency_map", "rows", 0, "country_name")
    assert_equal 41, data.dig("chokepoint", "supply_chain_lens", "reserve_runway", "cards", 0, "runway_days")
    assert_equal "Day 1", data.dig("chokepoint", "supply_chain_lens", "downstream_pathway", "stages", 0, "phase")
  end
end
