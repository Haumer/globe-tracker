class RefreshAreaReportSnapshotJob < ApplicationJob
  queue_as :default
  tracks_polling source: "derived-area-report", poll_type: "derived_layer"

  def perform(bounds)
    snapshot = AreaReportSnapshotService.refresh(bounds.symbolize_keys)
    count = snapshot.payload.is_a?(Hash) ? snapshot.payload.size : 0
    { records_fetched: count, records_stored: count }
  end
end
