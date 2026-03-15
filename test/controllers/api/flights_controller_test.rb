require "test_helper"

class Api::FlightsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @flight = Flight.create!(
      icao24: "abc123",
      callsign: "TEST01",
      latitude: 48.2,
      longitude: 16.3,
      altitude: 35000,
      speed: 450,
      heading: 90,
      origin_country: "Austria",
      on_ground: false,
      military: false,
      updated_at: Time.current,
    )
  end

  test "GET /api/flights returns JSON array" do
    get "/api/flights"
    assert_response :success

    data = JSON.parse(response.body)
    assert_kind_of Array, data
  end

  test "flights response contains expected fields" do
    get "/api/flights"
    data = JSON.parse(response.body)
    flight = data.find { |f| f["icao24"] == "abc123" }

    assert_not_nil flight
    assert_equal "TEST01", flight["callsign"]
    assert_in_delta 48.2, flight["latitude"], 0.01
    assert_in_delta 16.3, flight["longitude"], 0.01
    assert_equal false, flight["military"]
  end

  test "bounds filtering works" do
    get "/api/flights", params: { lamin: 47.0, lamax: 49.0, lomin: 15.0, lomax: 17.0 }
    data = JSON.parse(response.body)
    icaos = data.map { |f| f["icao24"] }
    assert_includes icaos, "abc123"

    get "/api/flights", params: { lamin: 0.0, lamax: 5.0, lomin: 0.0, lomax: 5.0 }
    data = JSON.parse(response.body)
    icaos = data.map { |f| f["icao24"] }
    assert_not_includes icaos, "abc123"
  end

  test "stale flights are excluded" do
    Flight.create!(
      icao24: "old999",
      callsign: "OLD01",
      latitude: 48.0, longitude: 16.0,
      altitude: 30000, speed: 400,
      origin_country: "Germany",
      military: false,
      updated_at: 5.minutes.ago,
    )

    get "/api/flights"
    data = JSON.parse(response.body)
    icaos = data.map { |f| f["icao24"] }
    assert_not_includes icaos, "old999"
  end
end
