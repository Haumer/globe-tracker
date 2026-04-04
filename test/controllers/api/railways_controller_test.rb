require "test_helper"

class Api::RailwaysControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_disabled_layers = LayerAvailability.disabled_layers
    @railway = Railway.create!(
      category: 0,
      electrified: 1,
      continent: "europe",
      min_lat: 47.0,
      max_lat: 48.0,
      min_lng: 15.0,
      max_lng: 17.0,
      coordinates: [[15.5, 47.5], [16.5, 47.8]]
    )
  end

  teardown do
    LayerAvailability.disabled_layers = @original_disabled_layers
  end

  test "GET /api/railways returns empty while the layer is disabled" do
    get "/api/railways"
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal [], data
  end

  test "GET /api/railways returns railway segments when enabled" do
    LayerAvailability.disabled_layers = []

    get "/api/railways"
    assert_response :success

    data = JSON.parse(response.body)
    assert_kind_of Array, data
    assert_equal 1, data.size
  end

  test "GET /api/railways with bbox filters by bounding box when enabled" do
    LayerAvailability.disabled_layers = []

    get "/api/railways", params: { bbox: "47.0,15.0,48.0,17.0" }
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal 1, data.size
  end

  test "GET /api/railways with non-overlapping bbox returns empty when enabled" do
    LayerAvailability.disabled_layers = []

    get "/api/railways", params: { bbox: "0.0,0.0,1.0,1.0" }
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal 0, data.size
  end
end
