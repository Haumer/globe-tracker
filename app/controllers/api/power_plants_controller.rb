module Api
  class PowerPlantsController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      # Static data — one full dump, cached client-side
      # Slim payload: ~1.5MB for 35k plants
      plants = PowerPlant.order(capacity_mw: :desc)
        .select(:id, :name, :latitude, :longitude, :primary_fuel, :capacity_mw, :country_code)

      expires_in 1.hour, public: true
      render json: plants.map { |p|
        [p.id, p.latitude, p.longitude, p.primary_fuel, p.capacity_mw, p.name, p.country_code]
      }
    end
  end
end
