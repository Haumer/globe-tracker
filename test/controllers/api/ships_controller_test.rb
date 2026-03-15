require "test_helper"

class Api::ShipsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @ship = Ship.create!(
      mmsi: "211000001",
      name: "MV Test Vessel",
      ship_type: 70,
      latitude: 54.0,
      longitude: 10.0,
      speed: 12.5,
      heading: 180,
      course: 175,
      destination: "HAMBURG",
      flag: "DE",
      updated_at: Time.current,
    )
  end

  test "GET /api/ships returns JSON array" do
    get "/api/ships"
    assert_response :success

    data = JSON.parse(response.body)
    assert_kind_of Array, data
  end

  test "ships response contains expected fields" do
    get "/api/ships", params: { lamin: 53.0, lamax: 55.0, lomin: 9.0, lomax: 11.0 }
    data = JSON.parse(response.body)
    ship = data.find { |s| s["mmsi"] == "211000001" }

    assert_not_nil ship
    assert_equal "MV Test Vessel", ship["name"]
    assert_in_delta 54.0, ship["latitude"], 0.01
  end

  test "stale ships are excluded" do
    Ship.create!(
      mmsi: "211000002",
      name: "Old Vessel",
      latitude: 54.0, longitude: 10.0,
      speed: 0, heading: 0,
      updated_at: 8.hours.ago,
    )

    get "/api/ships", params: { lamin: 53.0, lamax: 55.0, lomin: 9.0, lomax: 11.0 }
    data = JSON.parse(response.body)
    mmsis = data.map { |s| s["mmsi"] }
    assert_not_includes mmsis, "211000002"
  end
end
