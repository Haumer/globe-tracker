require "test_helper"

class RefreshFlightRouteJobTest < ActiveSupport::TestCase
  test "is assigned to the default queue" do
    assert_equal "default", RefreshFlightRouteJob.new.queue_name
  end

  test "calls FlightRouteRefreshService.refresh with callsign and icao24" do
    called_with = nil
    mock = ->(**kwargs) { called_with = kwargs; nil }

    FlightRouteRefreshService.stub(:refresh, mock) do
      RefreshFlightRouteJob.perform_now("UAL123", "abc123")
    end

    assert_equal "UAL123", called_with[:callsign]
    assert_equal "abc123", called_with[:flight_icao24]
    assert_equal true, called_with[:force]
  end

  test "passes nil for flight_icao24 when not provided" do
    called_with = nil
    mock = ->(**kwargs) { called_with = kwargs; nil }

    FlightRouteRefreshService.stub(:refresh, mock) do
      RefreshFlightRouteJob.perform_now("UAL123")
    end

    assert_nil called_with[:flight_icao24]
  end
end
