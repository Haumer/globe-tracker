module Api
  class CommoditySitesController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      sites = CommoditySiteCatalog.all
      response.headers["ETag"] = CommoditySiteCatalog.etag
      expires_in 12.hours, public: true
      render json: { commodity_sites: sites }
    end
  end
end
