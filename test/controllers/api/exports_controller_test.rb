require "test_helper"
require "csv"

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

  test "GET /api/exports/csv applies bounds to earthquakes" do
    Earthquake.create!(
      external_id: "eq-in",
      title: "Inside",
      magnitude: 5.1,
      latitude: 10.0,
      longitude: 20.0,
      depth: 12.0,
      event_time: 30.minutes.ago
    )
    Earthquake.create!(
      external_id: "eq-out",
      title: "Outside",
      magnitude: 4.8,
      latitude: -15.0,
      longitude: 120.0,
      depth: 8.0,
      event_time: 30.minutes.ago
    )

    get "/api/exports/csv", params: {
      layer: "earthquakes",
      lamin: 5,
      lamax: 15,
      lomin: 15,
      lomax: 25,
    }

    assert_response :success
    rows = CSV.parse(response.body, headers: true)
    assert_equal ["eq-in"], rows.map { |row| row["external_id"] }
  end

  test "GET /api/exports/flight_history returns flight route" do
    get "/api/exports/flight_history/abc123"
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal "abc123", data["entity_id"]
    assert_kind_of Array, data["route"]
  end

  test "GET /api/exports/flight_history clamps to the recent export window" do
    PositionSnapshot.create!(
      entity_type: "flight",
      entity_id: "abc123",
      callsign: "TEST123",
      latitude: 10.0,
      longitude: 20.0,
      recorded_at: 10.days.ago
    )
    PositionSnapshot.create!(
      entity_type: "flight",
      entity_id: "abc123",
      callsign: "TEST123",
      latitude: 11.0,
      longitude: 21.0,
      recorded_at: 2.days.ago
    )

    get "/api/exports/flight_history/abc123", params: {
      from: 14.days.ago.iso8601,
      to: Time.current.iso8601,
    }

    assert_response :success
    data = JSON.parse(response.body)
    assert_equal 1, data["route"].size
    assert_equal 11.0, data["route"].first["lat"]
  end

  test "GET /api/exports/csv rejects unsupported layer" do
    get "/api/exports/csv", params: { layer: "ports" }

    assert_response :unprocessable_content
    data = JSON.parse(response.body)
    assert_equal "Unsupported export layer", data["error"]
    assert_includes data["allowed_layers"], "earthquakes"
  end

  test "unauthenticated request is redirected" do
    sign_out @user
    get "/api/exports/geojson"
    assert_response :redirect
  end
end
