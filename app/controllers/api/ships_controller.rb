module Api
  class ShipsController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      bounds = {
        lamin: params[:lamin]&.to_f,
        lamax: params[:lamax]&.to_f,
        lomin: params[:lomin]&.to_f,
        lomax: params[:lomax]&.to_f
      }.compact

      ships = Ship.where.not(latitude: nil, longitude: nil)
                  .within_bounds(bounds)
                  .where("updated_at > ?", 6.hours.ago)

      render json: ships.select(:mmsi, :name, :ship_type, :latitude, :longitude,
                                :speed, :heading, :course, :destination, :flag,
                                :updated_at).limit(10000)
    end
  end
end
