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

      # Route lookup cached in Redis — external API call only on cache miss
      route = Rails.cache.fetch("flight_route:#{callsign}", expires_in: 30.minutes) do
        ::OpenskyService.fetch_route(callsign)
      end
      detail[:route] = route unless route[:error]

      render json: detail
    end
  end
end
