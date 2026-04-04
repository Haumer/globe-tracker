module Api
  class ShipsController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      configured = ENV["AISSTREAM_API_KEY"].present?
      ships = Ship.where.not(latitude: nil, longitude: nil)
                  .within_bounds(parse_bounds)
                  .where("updated_at > ?", 6.hours.ago)

      expires_in 30.seconds, public: true
      response.set_header("X-Source-Configured", configured ? "1" : "0")
      response.set_header("X-Source-Status", ships.exists? ? "ready" : (configured ? "empty" : "unconfigured"))

      render json: ships.select(:mmsi, :name, :ship_type, :latitude, :longitude,
                                :speed, :heading, :course, :destination, :flag,
                                :updated_at).limit(10000)
    end
  end
end
