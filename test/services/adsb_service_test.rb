require "test_helper"

class AdsbServiceTest < ActiveSupport::TestCase
  test "upsert_flights with valid aircraft data creates flights" do
    data = {
      "ac" => [
        {
          "hex" => "aabbcc",
          "flight" => "UAL123 ",
          "lat" => 40.7,
          "lon" => -73.9,
          "alt_geom" => 35000,
          "gs" => 450,
          "track" => 180,
          "baro_rate" => 0,
          "seen" => 2,
          "r" => "N12345",
          "t" => "B738",
          "squawk" => "1200",
        }
      ]
    }

    assert_difference "Flight.count" do
      AdsbService.send(:upsert_flights, data)
    end

    flight = Flight.find_by(icao24: "aabbcc")
    assert_not_nil flight
    assert_equal "UAL123", flight.callsign
    assert_equal "adsb", flight.source
    assert_equal "N12345", flight.registration
    assert_equal "B738", flight.aircraft_type
  end

  test "upsert_flights skips aircraft without coordinates" do
    data = {
      "ac" => [
        { "hex" => "000000", "flight" => "TEST", "lat" => nil, "lon" => nil, "seen" => 5 }
      ]
    }

    assert_no_difference "Flight.count" do
      AdsbService.send(:upsert_flights, data)
    end
  end

  test "upsert_flights skips stale aircraft seen > 60s ago" do
    data = {
      "ac" => [
        { "hex" => "stale1", "flight" => "OLD", "lat" => 40.0, "lon" => -74.0, "seen" => 120 }
      ]
    }

    assert_no_difference "Flight.count" do
      AdsbService.send(:upsert_flights, data)
    end
  end

  test "upsert_flights handles empty aircraft array" do
    assert_nothing_raised do
      AdsbService.send(:upsert_flights, { "ac" => nil })
      AdsbService.send(:upsert_flights, { "ac" => [] })
    end
  end

  test "upsert_flights converts altitude from feet to meters" do
    data = {
      "ac" => [
        { "hex" => "conv01", "lat" => 40.0, "lon" => -74.0, "alt_geom" => 10000, "seen" => 0 }
      ]
    }

    AdsbService.send(:upsert_flights, data)
    flight = Flight.find_by(icao24: "conv01")
    # 10000 ft * 0.3048 = 3048.0 m
    assert_in_delta 3048.0, flight.altitude, 1.0
  end
end
