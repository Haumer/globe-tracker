class RefreshChokepointsSnapshotJob < ApplicationJob
  queue_as :default
  tracks_polling source: "derived-chokepoints", poll_type: "derived_layer"

  def perform
    snapshot = ChokepointSnapshotService.refresh
    count = Array(snapshot.payload["chokepoints"] || snapshot.payload[:chokepoints]).size
    { records_fetched: count, records_stored: count }
  end
end
