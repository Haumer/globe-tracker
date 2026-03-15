require "test_helper"

class AirportTest < ActiveSupport::TestCase
  test "creation with required fields" do
    airport = Airport.create!(
      icao_code: "LOWW",
      name: "Vienna International Airport",
      airport_type: "large_airport",
      latitude: 48.1103,
      longitude: 16.5697
    )
    assert airport.persisted?
    assert_equal "LOWW", airport.icao_code
  end

  test "within_bounds filters by latitude and longitude" do
    Airport.create!(icao_code: "LOWW", name: "Vienna", airport_type: "large_airport", latitude: 48.1, longitude: 16.5)
    Airport.create!(icao_code: "KJFK", name: "JFK", airport_type: "large_airport", latitude: 40.6, longitude: -73.7)

    bounds = { lamin: 47.0, lamax: 49.0, lomin: 15.0, lomax: 17.0 }
    results = Airport.within_bounds(bounds)

    assert_equal 1, results.count
    assert_equal "LOWW", results.first.icao_code
  end

  test "military scope returns only military airports" do
    Airport.create!(icao_code: "LOWW", name: "Vienna", airport_type: "large_airport", latitude: 48.1, longitude: 16.5, is_military: false)
    Airport.create!(icao_code: "LOXZ", name: "Zeltweg AFB", airport_type: "military", latitude: 47.2, longitude: 14.7, is_military: true)

    assert_equal 1, Airport.military.count
    assert_equal "LOXZ", Airport.military.first.icao_code
  end

  test "civilian scope returns only civilian airports" do
    Airport.create!(icao_code: "LOWW", name: "Vienna", airport_type: "large_airport", latitude: 48.1, longitude: 16.5, is_military: false)
    Airport.create!(icao_code: "LOXZ", name: "Zeltweg AFB", airport_type: "military", latitude: 47.2, longitude: 14.7, is_military: true)

    assert_equal 1, Airport.civilian.count
    assert_equal "LOWW", Airport.civilian.first.icao_code
  end

  test "by_type scope filters by airport_type" do
    Airport.create!(icao_code: "LOWW", name: "Vienna", airport_type: "large_airport", latitude: 48.1, longitude: 16.5)
    Airport.create!(icao_code: "LOWG", name: "Graz", airport_type: "medium_airport", latitude: 46.9, longitude: 15.4)

    assert_equal 1, Airport.by_type("large_airport").count
  end
end
