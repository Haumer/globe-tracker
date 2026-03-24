class RefreshFlightRouteJob < ApplicationJob
  queue_as :default

  def perform(callsign, flight_icao24 = nil)
    FlightRouteRefreshService.refresh(callsign: callsign, flight_icao24: flight_icao24, force: true)
  end
end
