class RefreshPlaceGazetteerJob < ApplicationJob
  queue_as :background
  tracks_polling source: "place-gazetteer", poll_type: "static_places"

  def perform
    PlaceGazetteerSyncService.refresh_if_stale
  end
end
