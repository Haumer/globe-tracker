class RefreshRailwaysJob < ApplicationJob
  queue_as :background
  tracks_polling source: "natural-earth", poll_type: "railways"

  def perform
    return if Railway.count > 0 # Static dataset — only import once
    RailwayImportService.import!
  end
end
