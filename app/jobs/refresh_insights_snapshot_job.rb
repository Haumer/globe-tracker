class RefreshInsightsSnapshotJob < ApplicationJob
  queue_as :default
  tracks_polling source: "derived-insights", poll_type: "derived_layer"

  def perform
    snapshot = InsightSnapshotService.refresh
    count = Array(snapshot.payload["insights"] || snapshot.payload[:insights]).size
    { records_fetched: count, records_stored: count }
  end
end
