class RefreshFireHotspotsJob < ApplicationJob
  queue_as :default

  def perform
    FirmsRefreshService.refresh_if_stale
  end
end
