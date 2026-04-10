module Api
  class RegionalAreaIndicatorsController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      records = RegionalAreaIndicatorCatalog.filtered(
        region_key: params[:region_key],
        comparable_level: params[:comparable_level] || "region"
      )

      response.headers["ETag"] = RegionalAreaIndicatorCatalog.etag(
        region_key: params[:region_key],
        comparable_level: params[:comparable_level] || "region"
      )
      expires_in 12.hours, public: true
      render json: records
    end
  end
end
