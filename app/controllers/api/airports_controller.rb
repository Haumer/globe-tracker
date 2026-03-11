module Api
  class AirportsController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      enqueue_background_refresh(RefreshAirportsJob, key: "airports", debounce: 1.hour) if OurAirportsService.stale?

      airports = Airport.all
      airports = airports.by_type(params[:type]) if params[:type].present?
      airports = airports.within_bounds(bounds_params) if bounds_params.present?
      airports = airports.order(airport_type: :asc, name: :asc)

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

    private

    def bounds_params
      if params[:lamin].present? && params[:lamax].present? &&
         params[:lomin].present? && params[:lomax].present?
        {
          lamin: params[:lamin].to_f,
          lamax: params[:lamax].to_f,
          lomin: params[:lomin].to_f,
          lomax: params[:lomax].to_f,
        }
      end
    end
  end
end
