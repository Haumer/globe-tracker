module Api
  class PipelinesController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      enqueue_background_refresh(RefreshPipelinesJob, key: "pipelines", debounce: 1.hour) if PipelineRefreshService.stale?

      pipelines = Pipeline.all
      render json: {
        pipelines: pipelines.map { |p|
          {
            id: p.pipeline_id,
            name: p.name,
            type: p.pipeline_type,
            status: p.status,
            length_km: p.length_km,
            color: p.color,
            country: p.country,
            coordinates: p.coordinates,
          }
        },
      }
    end
  end
end
