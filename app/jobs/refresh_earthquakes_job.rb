class RefreshEarthquakesJob < ApplicationJob
  queue_as :default

  def perform
    EarthquakeRefreshService.refresh_if_stale
  end
end
