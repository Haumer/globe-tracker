module Api
  class TrainsController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      trains = Rails.cache.fetch("hafas_trains:#{params[:bbox]}", expires_in: 10.seconds) do
        HafasTrainService.fetch(bbox: params[:bbox])
      end
      render json: trains
    end
  end
end
