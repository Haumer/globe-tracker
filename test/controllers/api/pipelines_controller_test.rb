require "test_helper"

class Api::PipelinesControllerTest < ActionDispatch::IntegrationTest
  test "GET /api/pipelines returns pipeline data" do
    Pipeline.create!(
      pipeline_id: "pipe-001",
      name: "Nord Stream",
      pipeline_type: "gas",
      status: "active",
      length_km: 1224.0,
      coordinates: [[10.0, 55.0], [12.0, 54.0]],
      color: "#ff0000",
      country: "Germany"
    )
    CommodityPrice.create!(
      symbol: "GAS_NAT",
      category: "commodity",
      name: "Natural Gas",
      price: 2.9,
      change_pct: 1.2,
      unit: "USD/MMBtu",
      region: "North America",
      recorded_at: Time.current
    )
    CountryCommodityDependency.create!(
      country_code_alpha3: "DEU",
      country_name: "Germany",
      commodity_key: "gas_nat",
      commodity_name: "Natural Gas",
      dependency_score: 0.72
    )
    CountryChokepointExposure.create!(
      country_code_alpha3: "DEU",
      country_name: "Germany",
      commodity_key: "gas_nat",
      commodity_name: "Natural Gas",
      chokepoint_key: "hormuz",
      chokepoint_name: "Strait of Hormuz",
      exposure_score: 0.41
    )

    get "/api/pipelines"
    assert_response :success

    data = JSON.parse(response.body)
    assert_kind_of Array, data["pipelines"]
    assert_equal 1, data["pipelines"].size
    assert_equal "Nord Stream", data["pipelines"].first["name"]
    assert_includes data["pipelines"].first.dig("market_context", "benchmarks").map { |entry| entry["symbol"] }, "GAS_NAT"
    assert_equal "Germany", data["pipelines"].first.dig("market_context", "downstream_countries", 0, "country_name")
    assert_equal "Strait of Hormuz", data["pipelines"].first.dig("market_context", "route_pressure", 0, "chokepoint_name")
    assert_kind_of Array, data["pipelines"].first.dig("market_context", "highlights")
  end

  test "GET /api/pipelines with empty DB returns empty array" do
    get "/api/pipelines"
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal [], data["pipelines"]
  end

  test "GET /api/pipelines/:id returns detailed market lens data" do
    Pipeline.create!(
      pipeline_id: "pipe-002",
      name: "Trans-Med",
      pipeline_type: "oil",
      status: "operational",
      length_km: 2475.0,
      coordinates: [[31.0, 10.0], [33.0, 14.0]],
      color: "#ff8a00",
      country: "Libya"
    )

    6.times do |idx|
      CommodityPrice.create!(
        symbol: "OIL_BRENT",
        category: "commodity",
        name: "Brent Crude",
        price: 100.0 + idx,
        change_pct: 0.5 + idx,
        unit: "USD/barrel",
        region: "North Sea",
        recorded_at: (6 - idx).hours.ago
      )
    end

    CountryCommodityDependency.create!(
      country_code_alpha3: "ITA",
      country_name: "Italy",
      commodity_key: "oil_crude",
      commodity_name: "Crude Oil",
      dependency_score: 0.58,
      metadata: { estimated: true }
    )

    CountryChokepointExposure.create!(
      country_code_alpha3: "ITA",
      country_name: "Italy",
      commodity_key: "oil_crude",
      commodity_name: "Crude Oil",
      chokepoint_key: "suez",
      chokepoint_name: "Suez Canal",
      exposure_score: 0.44,
      metadata: { estimated: true }
    )

    get "/api/pipelines/pipe-002"
    assert_response :success

    data = JSON.parse(response.body)
    lens = data.dig("pipeline", "market_context")

    assert_equal "Trans-Med", data.dig("pipeline", "name")
    assert_equal "oil", data.dig("pipeline", "type")
    assert_equal "critical", lens["risk_level"]
    assert_kind_of Array, lens["highlights"]
    assert_operator lens.dig("benchmark_series", "OIL_BRENT").length, :>=, 2
    assert_equal 0, lens.dig("coverage", "downstream_observed")
    assert_equal 1, lens.dig("coverage", "downstream_estimated")
  end
end
