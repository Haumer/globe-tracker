module Api
  class SatellitesController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      category = params[:category].presence
      if CelestrakService.stale?(category: category)
        enqueue_background_refresh(RefreshSatellitesJob, category, key: "satellites:#{category || 'all'}", debounce: 5.minutes)
      end

      satellites = Satellite.all
      satellites = satellites.where(category: category) if category.present?

      render json: satellites.select(:name, :tle_line1, :tle_line2, :category, :norad_id, :operator, :mission_type)
    end
  end
end
