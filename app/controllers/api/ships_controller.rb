module Api
  class ShipsController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      ships = Ship.where.not(latitude: nil, longitude: nil)

      if params[:lamin].present?
        ships = ships.where(latitude: params[:lamin].to_f..params[:lamax].to_f,
                            longitude: params[:lomin].to_f..params[:lomax].to_f)
      end

      # Only return ships updated in the last 10 minutes (stale data = gone)
      ships = ships.where("updated_at > ?", 10.minutes.ago)

      render json: ships.select(:mmsi, :name, :ship_type, :latitude, :longitude,
                                :speed, :heading, :course, :destination, :flag,
                                :updated_at).limit(5000)
    end
  end
end
