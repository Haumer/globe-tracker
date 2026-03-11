class RefreshSatellitesJob < ApplicationJob
  queue_as :default

  def perform(category = nil)
    CelestrakService.refresh_if_stale(category: category.presence)
  end
end
