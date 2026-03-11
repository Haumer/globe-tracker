class RefreshInternetTrafficJob < ApplicationJob
  queue_as :default

  def perform
    CloudflareRadarService.refresh_if_stale
  end
end
