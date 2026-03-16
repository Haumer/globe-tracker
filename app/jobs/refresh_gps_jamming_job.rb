class RefreshGpsJammingJob < ApplicationJob
  queue_as :default

  def perform
    GpsJammingRefreshService.refresh_if_stale
  end
end
