module Api
  class ConnectionsController < ApplicationController
    skip_before_action :authenticate_user!

    def show
      result = ConnectionFinder.find(
        entity_type: params[:entity_type],
        lat: params[:lat],
        lng: params[:lng],
        metadata: params[:metadata]&.to_unsafe_h || {}
      )
      render json: result
    end
  end
end
