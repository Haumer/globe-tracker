module Api
  class RegionalAdminProfilesController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      records = RegionalAdminProfileCatalog.filtered(
        region_key: params[:region_key],
        country_codes: params[:country_codes]
      )

      response.headers["ETag"] = RegionalAdminProfileCatalog.etag
      expires_in 6.hours, public: true
      render json: records
    end
  end
end
