module Api
  class RegionalIndicatorsController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      records = RegionalIndicatorCatalog.filtered(
        country_codes: params[:country_codes],
        country_names: params[:country_names]
      )

      response.headers["ETag"] = RegionalIndicatorCatalog.etag
      expires_in 6.hours, public: true
      render json: records
    end
  end
end
