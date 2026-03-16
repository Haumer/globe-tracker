module Api
  class AirportsController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      airports = Airport.all
      airports = airports.by_type(params[:type]) if params[:type].present?
      bounds = parse_bounds
      airports = airports.within_bounds(bounds) if bounds.present?
      airports = airports.order(airport_type: :asc, name: :asc).limit(5000)

      expires_in 1.hour, public: true
      render json: airports.map { |a|
        {
          icao: a.icao_code,
          iata: a.iata_code,
          name: a.name,
          type: a.airport_type,
          lat: a.latitude,
          lng: a.longitude,
          elevation: a.elevation_ft,
          country: a.country_code,
          municipality: a.municipality,
          military: a.is_military,
        }
      }
    end
  end
end
