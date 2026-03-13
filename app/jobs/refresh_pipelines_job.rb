class RefreshPipelinesJob < ApplicationJob
  queue_as :default

  def perform
    PipelineRefreshService.refresh_if_stale
  end
end
