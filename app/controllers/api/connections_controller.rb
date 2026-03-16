module Api
  class ConnectionsController < ApplicationController
    skip_before_action :authenticate_user!

    def show
      cache_key = "connections:#{params[:entity_type]}:#{params[:lat]}:#{params[:lng]}:#{Digest::MD5.hexdigest((params[:metadata]&.to_unsafe_h || {}).sort.to_s)}"
      result = Rails.cache.fetch(cache_key, expires_in: 5.minutes) do
        ConnectionFinder.find(
          entity_type: params[:entity_type],
          lat: params[:lat],
          lng: params[:lng],
          metadata: params[:metadata]&.to_unsafe_h || {}
        )
      end
      expires_in 5.minutes, public: true
      render json: result
    end
  end
end
