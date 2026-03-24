class RefreshEarthquakesJob < ApplicationJob
  queue_as :default
  tracks_polling source: "usgs", poll_type: "earthquakes"

  def perform
    EarthquakeRefreshService.refresh_if_stale
  end
end
