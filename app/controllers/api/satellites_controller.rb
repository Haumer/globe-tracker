module Api
  class SatellitesController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      satellites = ::CelestrakService.fetch_satellites(category: params[:category])

      render json: satellites.select(:name, :tle_line1, :tle_line2, :category, :norad_id)
    end
  end
end
