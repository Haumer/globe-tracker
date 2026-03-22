module Api
  class PowerPlantsController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      # Static data — one full dump, cached client-side
      # Slim payload: ~1.5MB for 35k plants
      plants = PowerPlant.order(capacity_mw: :desc)
        .select(:id, :name, :latitude, :longitude, :primary_fuel, :capacity_mw, :country_code)

      data = plants.map { |p|
        [p.id, p.latitude, p.longitude, p.primary_fuel, p.capacity_mw, p.name, p.country_code]
      }

      if data.empty?
        expires_in 30.seconds, public: true
      else
        max_updated = PowerPlant.maximum(:updated_at)&.to_i || 0
        response.headers["ETag"] = Digest::MD5.hexdigest("pp:#{data.size}:#{max_updated}")
        expires_in 1.hour, public: true
      end
      render json: data
    end
  end
end
