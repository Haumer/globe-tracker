class RefreshFireHotspotsJob < ApplicationJob
  queue_as :default
  tracks_polling source: "firms", poll_type: "fire_hotspots"

  def perform
    FirmsRefreshService.refresh_if_stale
  end
end
