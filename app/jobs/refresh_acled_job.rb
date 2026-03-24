class RefreshAcledJob < ApplicationJob
  queue_as :default
  tracks_polling source: "acled", poll_type: "conflict_events"

  def perform
    AcledService.refresh_if_stale
  end
end
