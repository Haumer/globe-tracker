class RefreshNaturalEventsJob < ApplicationJob
  queue_as :default

  def perform
    NaturalEventRefreshService.refresh_if_stale
  end
end
