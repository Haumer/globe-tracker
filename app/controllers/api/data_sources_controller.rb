module Api
  class DataSourcesController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      records = DataSourceRegistry.filtered(
        country_codes: params[:country_codes],
        region_key: params[:region_key],
        statuses: params[:status],
        target_models: params[:target_model]
      )

      response.headers["ETag"] = DataSourceRegistry.etag
      expires_in 12.hours, public: true
      render json: records
    end
  end
end
