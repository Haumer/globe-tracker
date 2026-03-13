module Api
  class SatellitesController < ApplicationController
    skip_before_action :authenticate_user!

    def search
      q = params[:q].to_s.strip
      return render json: [] if q.length < 2

      sats = Satellite.where("name ILIKE ? OR CAST(norad_id AS TEXT) LIKE ?", "%#{q}%", "#{q}%")
                       .limit(8)
                       .select(:name, :tle_line1, :tle_line2, :category, :norad_id, :operator, :mission_type,
                               :country_owner, :users, :purpose, :detailed_purpose, :orbit_class,
                               :launch_date, :launch_site, :launch_vehicle, :contractor, :expected_lifetime)
      render json: sats
    end

    def index
      category = params[:category].presence
      if CelestrakService.stale?(category: category)
        enqueue_background_refresh(RefreshSatellitesJob, category, key: "satellites:#{category || 'all'}", debounce: 5.minutes)
      end

      satellites = Satellite.all
      satellites = satellites.where(category: category) if category.present?

      render json: satellites.select(:name, :tle_line1, :tle_line2, :category, :norad_id, :operator, :mission_type,
                                      :country_owner, :users, :purpose, :detailed_purpose, :orbit_class,
                                      :launch_date, :launch_site, :launch_vehicle, :contractor, :expected_lifetime)
    end
  end
end
