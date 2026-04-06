module Api
  class ShipsController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      configured = ENV["AISSTREAM_API_KEY"].present?
      ships = Ship.where.not(latitude: nil, longitude: nil)
                  .within_bounds(parse_bounds)
                  .where("updated_at > ?", 6.hours.ago)
                  .limit(10_000)

      ship_rows = ships.to_a
      ship_rows = case params[:filter]
      when "naval"
        ship_rows.select(&:naval_vessel?)
      when "civilian"
        ship_rows.reject(&:naval_vessel?)
      else
        ship_rows
      end

      expires_in 30.seconds, public: true
      response.set_header("X-Source-Configured", configured ? "1" : "0")
      response.set_header("X-Source-Status", ship_rows.any? ? "ready" : (configured ? "empty" : "unconfigured"))

      render json: ship_rows.map { |ship|
        {
          mmsi: ship.mmsi,
          name: ship.name,
          ship_type: ship.ship_type,
          latitude: ship.latitude,
          longitude: ship.longitude,
          speed: ship.speed,
          heading: ship.heading,
          course: ship.course,
          destination: ship.destination,
          flag: ship.flag,
          updated_at: ship.updated_at,
        }
      }
    end
  end
end
