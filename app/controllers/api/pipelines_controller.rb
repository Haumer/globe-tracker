module Api
  class PipelinesController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      pipelines = Pipeline.all
      render json: {
        pipelines: pipelines.map { |p| serialize_pipeline(p) },
      }
    end

    def show
      pipeline = Pipeline.find_by!(pipeline_id: params[:id])

      render json: {
        pipeline: serialize_pipeline(pipeline, detail: true),
      }
    end

    private

    def serialize_pipeline(pipeline, detail: false)
      {
        id: pipeline.pipeline_id,
        name: pipeline.name,
        type: pipeline.pipeline_type,
        status: pipeline.status,
        length_km: pipeline.length_km,
        color: pipeline.color,
        country: pipeline.country,
        coordinates: pipeline.coordinates,
        market_context: PipelineMarketContextService.call(pipeline, detail: detail),
      }
    end
  end
end
