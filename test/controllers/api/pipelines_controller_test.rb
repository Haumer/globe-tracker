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
  end

  test "GET /api/pipelines with empty DB returns empty array" do
    get "/api/pipelines"
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal [], data["pipelines"]
  end
end
