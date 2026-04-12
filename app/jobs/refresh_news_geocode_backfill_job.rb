class RefreshNewsGeocodeBackfillJob < ApplicationJob
  queue_as :background
  tracks_polling source: "news-geocode-backfill", poll_type: "repair"

  def perform
    NewsEventGeocodeBackfillService.backfill_recent
  end
end
