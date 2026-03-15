require "test_helper"

class OpenskyServiceTest < ActiveSupport::TestCase
  test "upsert_flights with valid state data creates flights" do
    data = {
      "states" => [
        ["abc123", "DLH123 ", "Germany", 1234567890, 1234567890,
         16.3, 48.2, 10000.0, false, 250.0, 90.0, 5.0, nil, 10000.0, nil, nil, nil]
      ]
    }

    assert_difference "Flight.count" do
      OpenskyService.send(:upsert_flights, data)
    end

    flight = Flight.find_by(icao24: "abc123")
    assert_not_nil flight
    assert_equal "DLH123", flight.callsign
    assert_equal "opensky", flight.source
  end

  test "upsert_flights skips states without coordinates" do
    data = {
      "states" => [
        ["xyz789", "TEST", "US", nil, nil, nil, nil, nil, false, nil, nil, nil, nil, nil, nil, nil, nil]
      ]
    }

    assert_no_difference "Flight.count" do
      OpenskyService.send(:upsert_flights, data)
    end
  end

  test "upsert_flights handles empty states" do
    assert_nothing_raised do
      OpenskyService.send(:upsert_flights, { "states" => nil })
      OpenskyService.send(:upsert_flights, { "states" => [] })
    end
  end

  test "BASE_URL is defined" do
    assert_not_nil OpenskyService::BASE_URL
  end
end
