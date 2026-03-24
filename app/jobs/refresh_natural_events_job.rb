class RefreshNaturalEventsJob < ApplicationJob
  queue_as :default
  tracks_polling source: "natural-events", poll_type: "natural_events"

  def perform
    NaturalEventRefreshService.refresh_if_stale
  end
end
