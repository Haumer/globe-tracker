require "test_helper"

class Api::ExportsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(email: "exports@example.com", password: "password123")
    sign_in @user
  end

  test "GET /api/exports/geojson returns geojson" do
    get "/api/exports/geojson", params: { layers: "flights" }
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal "FeatureCollection", data["type"]
    assert_kind_of Array, data["features"]
  end

  test "GET /api/exports/csv returns csv data" do
    get "/api/exports/csv", params: { layer: "earthquakes" }
    assert_response :success
    assert_match "text/csv", response.content_type
  end

  test "GET /api/exports/flight_history returns flight route" do
    get "/api/exports/flight_history/abc123"
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal "abc123", data["entity_id"]
    assert_kind_of Array, data["route"]
  end

  test "unauthenticated request is redirected" do
    sign_out @user
    get "/api/exports/geojson"
    assert_response :redirect
  end
end
