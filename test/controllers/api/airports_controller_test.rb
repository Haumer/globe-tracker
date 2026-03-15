require "test_helper"

class Api::AirportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @airport = Airport.create!(
      icao_code: "LOWW",
      iata_code: "VIE",
      name: "Vienna International Airport",
      airport_type: "large_airport",
      latitude: 48.1103,
      longitude: 16.5697,
      country_code: "AT",
      is_military: false
    )
  end

  test "GET /api/airports returns JSON array" do
    get "/api/airports"
    assert_response :success

    data = JSON.parse(response.body)
    assert_kind_of Array, data
  end

  test "response contains expected fields" do
    get "/api/airports"
    data = JSON.parse(response.body)
    airport = data.find { |a| a["icao"] == "LOWW" }

    assert_not_nil airport
    assert_equal "VIE", airport["iata"]
    assert_equal "Vienna International Airport", airport["name"]
    assert_equal "AT", airport["country"]
  end

  test "type filter works" do
    Airport.create!(icao_code: "LOXZ", name: "Zeltweg", airport_type: "military", latitude: 47.2, longitude: 14.7, is_military: true)

    get "/api/airports", params: { type: "military" }
    data = JSON.parse(response.body)
    assert data.all? { |a| a["type"] == "military" }
  end

  test "bounds filtering works" do
    get "/api/airports", params: { lamin: 47.0, lamax: 49.0, lomin: 15.0, lomax: 17.0 }
    data = JSON.parse(response.body)
    assert data.any?

    get "/api/airports", params: { lamin: 0.0, lamax: 5.0, lomin: 0.0, lomax: 5.0 }
    data = JSON.parse(response.body)
    assert_empty data
  end
end
