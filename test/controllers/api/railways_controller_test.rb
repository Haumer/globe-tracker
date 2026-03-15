require "test_helper"

class Api::RailwaysControllerTest < ActionDispatch::IntegrationTest
  setup do
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

  test "GET /api/railways returns railway segments" do
    get "/api/railways"
    assert_response :success

    data = JSON.parse(response.body)
    assert_kind_of Array, data
    assert_equal 1, data.size
  end

  test "GET /api/railways with bbox filters by bounding box" do
    get "/api/railways", params: { bbox: "47.0,15.0,48.0,17.0" }
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal 1, data.size
  end

  test "GET /api/railways with non-overlapping bbox returns empty" do
    get "/api/railways", params: { bbox: "0.0,0.0,1.0,1.0" }
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal 0, data.size
  end
end
