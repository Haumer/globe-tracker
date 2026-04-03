require "test_helper"

class Api::PortsControllerTest < ActionDispatch::IntegrationTest
  include PortTestDataHelper

  test "GET /api/ports returns observed ports enriched with estimated goods" do
    create_port_trade_location
    create_country_dependency

    get "/api/ports"
    assert_response :success

    data = JSON.parse(response.body)
    port = data.fetch("ports").find { |item| item["locode"] == "JPTYO" }

    assert port.present?
    assert_equal false, port["estimated"]
    assert_equal "lng", port["primary_flow_type"]
    assert_equal "Tokyo, JP", port["map_label"]
    assert_equal "JP", port["place_label"]
    assert_includes port.fetch("estimated_commodity_names"), "Liquefied Natural Gas"
  end
end
