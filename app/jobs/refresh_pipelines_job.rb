class RefreshPipelinesJob < ApplicationJob
  queue_as :default
  tracks_polling source: "pipelines", poll_type: "pipelines"

  def perform
    PipelineRefreshService.refresh_if_stale
  end
end
