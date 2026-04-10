module Api
  class RegionalDistrictBoundariesController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      payload = RegionalDistrictBoundaryCatalog.feature_collection(
        country_codes: params[:country_codes]
      )

      response.headers["ETag"] = RegionalDistrictBoundaryCatalog.etag(
        country_codes: params[:country_codes]
      )
      expires_in 12.hours, public: true
      render json: payload
    end
  end
end
