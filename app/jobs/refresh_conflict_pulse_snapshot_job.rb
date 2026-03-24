class RefreshConflictPulseSnapshotJob < ApplicationJob
  queue_as :default
  tracks_polling source: "derived-conflict-pulse", poll_type: "derived_layer"

  def perform
    snapshot = ConflictPulseSnapshotService.refresh
    count = Array(snapshot.payload["zones"] || snapshot.payload[:zones]).size
    { records_fetched: count, records_stored: count }
  end
end
