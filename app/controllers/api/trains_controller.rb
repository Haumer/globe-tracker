module Api
  class TrainsController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      trains = OebbTrainService.fetch(bbox: params[:bbox])
      render json: trains
    end
  end
end
