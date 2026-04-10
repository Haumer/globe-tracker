module Api
  class PowerPlantProfilesController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      records = CuratedPowerPlantCatalog.filtered(country_codes: params[:country_codes])
      response.headers["ETag"] = CuratedPowerPlantCatalog.etag
      expires_in 12.hours, public: true
      render json: records
    end
  end
end
