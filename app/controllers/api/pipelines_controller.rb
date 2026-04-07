module Api
  class PipelinesController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      pipelines = Pipeline.all
      render json: {
        pipelines: pipelines.map { |p|
          market_context = PipelineMarketContextService.call(p)
          {
            id: p.pipeline_id,
            name: p.name,
            type: p.pipeline_type,
            status: p.status,
            length_km: p.length_km,
            color: p.color,
            country: p.country,
            coordinates: p.coordinates,
            market_context: market_context,
          }
        },
      }
    end
  end
end
