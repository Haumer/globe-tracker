module Api
  class NodeContextsController < ApplicationController
    skip_before_action :authenticate_user!

    rescue_from NodeContextService::UnsupportedNodeError do |error|
      render json: { error: error.message }, status: :unprocessable_entity
    end

    rescue_from NodeContextService::NodeNotFoundError do |error|
      render json: { error: error.message }, status: :not_found
    end

    def show
      render json: NodeContextService.resolve(
        kind: params[:kind],
        id: params[:id]
      )
    end
  end
end
