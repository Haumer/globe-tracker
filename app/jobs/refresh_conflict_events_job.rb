class RefreshConflictEventsJob < ApplicationJob
  queue_as :default
  tracks_polling source: "ucdp", poll_type: "conflict_events"

  def perform
    ConflictEventService.refresh_if_stale
  end
end
