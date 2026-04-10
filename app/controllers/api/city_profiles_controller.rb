module Api
  class CityProfilesController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      records = RegionalCityProfileCatalog.filtered(country_codes: params[:country_codes])
      response.headers["ETag"] = RegionalCityProfileCatalog.etag
      expires_in 12.hours, public: true
      render json: records
    end
  end
end
