module Api
  class SatellitesController < ApplicationController
    skip_before_action :authenticate_user!

    SATELLITE_FIELDS = %i[
      name
      tle_line1
      tle_line2
      category
      norad_id
      operator
      mission_type
      country_owner
      users
      purpose
      detailed_purpose
      orbit_class
      launch_date
      launch_site
      launch_vehicle
      contractor
      expected_lifetime
    ].freeze

    def search
      q = params[:q].to_s.strip
      return render json: [] if q.length < 2

      sats = Satellite.all
      sats = sats.observation_capable if observing_only?
      sats = sats.where("name ILIKE ? OR CAST(norad_id AS TEXT) LIKE ?", "%#{q}%", "#{q}%")
                       .limit(8)
                       .select(*SATELLITE_FIELDS)
      render json: sats
    end

    def index
      category = params[:category].presence

      satellites = Satellite.all
      satellites = satellites.where(category: category) if category.present?
      satellites = satellites.observation_capable if observing_only?

      render json: satellites.select(*SATELLITE_FIELDS)
    end

    private

    def observing_only?
      ActiveModel::Type::Boolean.new.cast(params[:observing] || params[:observation])
    end
  end
end
