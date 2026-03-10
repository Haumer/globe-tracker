module Api
  class FlightsController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      bounds = {
        lamin: params[:lamin]&.to_f,
        lamax: params[:lamax]&.to_f,
        lomin: params[:lomin]&.to_f,
        lomax: params[:lomax]&.to_f
      }.compact

      flights = ::OpenskyService.fetch_flights(bounds: bounds)

      render json: flights.select(:icao24, :callsign, :latitude, :longitude,
                                  :altitude, :speed, :heading, :origin_country,
                                  :on_ground, :vertical_rate, :time_position,
                                  :updated_at)
    end

    def show
      callsign = params[:id]&.strip
      route = ::OpenskyService.fetch_route(callsign)
      render json: route
    end
  end
end
