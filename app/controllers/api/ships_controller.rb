module Api
  class ShipsController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      ships = Ship.where.not(latitude: nil, longitude: nil)
                  .within_bounds(parse_bounds)
                  .where("updated_at > ?", 6.hours.ago)

      render json: ships.select(:mmsi, :name, :ship_type, :latitude, :longitude,
                                :speed, :heading, :course, :destination, :flag,
                                :updated_at).limit(10000)
    end
  end
end
