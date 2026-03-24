module Api
  class FlightsController < ApplicationController
    skip_before_action :authenticate_user!

    # Map-essential columns — loaded every 10s for all visible flights
    LIST_COLUMNS = %i[
      icao24 callsign latitude longitude altitude speed heading
      origin_country on_ground vertical_rate time_position
      source military squawk emergency category
    ].freeze

    def index
      bounds = parse_bounds

      # Read from DB — the GlobalPollerService keeps flights fresh in the background
      flights = Flight.where("updated_at > ?", 2.minutes.ago).select(*LIST_COLUMNS)
      flights = flights.within_bounds(bounds) if bounds.present?
      flights = flights.where(military: true) if params[:filter] == "military"

      expires_in 5.seconds, public: true

      render json: flights.map { |f|
        {
          icao24: f.icao24,
          callsign: f.callsign,
          latitude: f.latitude,
          longitude: f.longitude,
          altitude: f.altitude,
          speed: f.speed,
          heading: f.heading,
          origin_country: f.origin_country,
          on_ground: f.on_ground,
          vertical_rate: f.vertical_rate,
          time_position: f.time_position,
          source: f.source,
          military: f.military,
          squawk: f.squawk,
          emergency: f.emergency,
          category: f.category,
        }
      }
    end

    def show
      callsign = params[:id]&.strip

      # Return full flight detail + route in one call
      flight = Flight.find_by("callsign = ? OR icao24 = ?", callsign, callsign)
      detail = flight ? flight.attributes.compact : {}
      lookup_callsign = flight&.callsign.presence || callsign
      route_record = lookup_callsign.present? ? FlightRoute.find_by(callsign: lookup_callsign.strip.upcase) : nil

      if route_record&.available?
        detail[:route] = route_record.payload
      elsif lookup_callsign.present?
        FlightRouteRefreshService.enqueue_if_needed(callsign: lookup_callsign, flight_icao24: flight&.icao24)
      end

      detail[:route_status] = route_status_for(route_record, lookup_callsign)
      detail[:route_fetched_at] = route_record&.fetched_at&.iso8601
      detail[:route_expires_at] = route_record&.expires_at&.iso8601
      detail[:route_error] = route_record&.error_code if route_record&.status == "failed"

      render json: detail
    end

    private

    def route_status_for(route_record, lookup_callsign)
      return "unavailable" if lookup_callsign.blank?
      return "available" if route_record&.available?
      return route_record.status if route_record.present?

      "pending"
    end
  end
end
