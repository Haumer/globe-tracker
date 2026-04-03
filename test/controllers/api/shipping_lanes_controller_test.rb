require "test_helper"

class Api::ShippingLanesControllerTest < ActionDispatch::IntegrationTest
  include ShippingLaneTestDataHelper

  setup do
    @original_disabled_layers = LayerAvailability.disabled_layers
  end

  teardown do
    LayerAvailability.disabled_layers = @original_disabled_layers
  end

  test "GET /api/shipping_lanes returns empty while the layer is disabled" do
    get "/api/shipping_lanes"
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal [], data["shipping_lanes"]
    assert_equal [], data["shipping_corridors"]
  end

  test "GET /api/shipping_lanes returns derived shipping lanes when enabled" do
    create_shipping_dependency
    create_shipping_exposure

    LayerAvailability.disabled_layers = []

    get "/api/shipping_lanes"
    assert_response :success

    data = JSON.parse(response.body)
    assert_kind_of Array, data["shipping_lanes"]
    assert_kind_of Array, data["shipping_corridors"]
    assert_equal 1, data["shipping_lanes"].size
    assert_equal "Liquefied Natural Gas", data["shipping_lanes"].first["commodity_name"]
    assert_equal "modeled", data["shipping_lanes"].first["status"]
    assert_equal "maritime_corridor_graph", data["shipping_lanes"].first.dig("metadata", "geometry_source")
    assert_operator data["shipping_lanes"].first.fetch("path_points").size, :>, 4
    assert_operator data["shipping_corridors"].size, :>, 10
  end

  test "GET /api/shipping_lanes returns the baseline corridor network without supply chain rows when enabled" do
    LayerAvailability.disabled_layers = []

    get "/api/shipping_lanes"
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal [], data["shipping_lanes"]
    assert_kind_of Array, data["shipping_corridors"]
    assert_operator data["shipping_corridors"].size, :>, 10
  end
end
