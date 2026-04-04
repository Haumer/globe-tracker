require "test_helper"

class PortMapServiceTest < ActiveSupport::TestCase
  include PortTestDataHelper

  test "infers likely goods for observed general trade ports from country dependencies" do
    create_port_trade_location
    create_country_dependency
    create_country_dependency(
      commodity_key: "oil_refined",
      commodity_name: "Refined Petroleum",
      dependency_score: 0.58
    )

    port = PortMapService.ports.find { |item| item[:locode] == "JPTYO" }

    assert port.present?
    assert_equal false, port[:estimated]
    assert_equal "regional", port[:importance_tier]
    assert_equal "lng", port[:primary_flow_type]
    assert_equal "Tokyo, JP", port[:map_label]
    assert_equal "JP", port[:place_label]
    assert_includes port[:estimated_commodity_keys], "lng"
    assert_includes port[:estimated_commodity_keys], "oil_refined"
    assert_includes port[:estimated_commodity_names], "Liquefied Natural Gas"
    assert_includes port[:country_dependency_commodities], "Liquefied Natural Gas"
  end

  test "merges observed ports with catalog priors for the same locode" do
    create_port_trade_location(
      locode: "USHOU",
      country_code: "US",
      country_code_alpha3: "USA",
      country_name: "United States",
      name: "Houston",
      normalized_name: "houston",
      latitude: 29.7604,
      longitude: -95.3698,
      metadata: {
        "flow_types" => ["oil"],
        "commodity_keys" => ["oil_crude"],
        "traffic_tons" => 50_000_000,
      }
    )

    port = PortMapService.ports.find { |item| item[:locode] == "USHOU" }

    assert port.present?
    assert_equal false, port[:estimated]
    assert_equal "oil", port[:primary_flow_type]
    assert_equal "Houston, US", port[:map_label]
    assert_includes port[:source], "test_feed"
    assert_includes port[:source], "catalog_prior"
    assert_includes port[:flow_types], "lng"
    assert_includes port[:roles], "trade_gateway"
    assert_includes port[:roles], "import"
    assert_includes port[:estimated_commodity_keys], "oil_crude"
  end
end
