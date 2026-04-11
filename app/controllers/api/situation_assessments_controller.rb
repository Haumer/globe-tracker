module Api
  class SituationAssessmentsController < ApplicationController
    skip_before_action :authenticate_user!

    rescue_from NodeContextService::UnsupportedNodeError do |error|
      render json: { error: error.message }, status: :unprocessable_entity
    end

    rescue_from NodeContextService::NodeNotFoundError do |error|
      render json: { error: error.message }, status: :not_found
    end

    def index
      render json: {
        situations: SituationAssessmentService.recent(limit: params.fetch(:limit, 12)),
        generated_at: Time.current.iso8601,
      }
    end

    def show
      render json: SituationAssessmentService.for_node(
        kind: params.require(:kind),
        id: params.require(:id)
      )
    end
  end
end
