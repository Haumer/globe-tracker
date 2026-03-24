class RefreshGpsJammingJob < ApplicationJob
  queue_as :default
  tracks_polling source: "gps-jamming", poll_type: "gps_jamming"

  def perform
    GpsJammingRefreshService.refresh_if_stale
  end
end
