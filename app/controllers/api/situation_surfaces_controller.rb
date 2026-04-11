module Api
  class SituationSurfacesController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      payload = SituationSurfaceService.build
      expires_in 2.minutes, public: true
      render json: payload
    end
  end
end
