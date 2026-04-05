class RefreshGeoconfirmedJob < ApplicationJob
  queue_as :background
  tracks_polling source: "geoconfirmed", poll_type: "geoconfirmed_events"

  def perform
    GeoconfirmedRefreshService.refresh_if_stale
  end
end
