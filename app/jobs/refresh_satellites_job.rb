class RefreshSatellitesJob < ApplicationJob
  queue_as :default
  tracks_polling source: "celestrak", poll_type: "satellites"

  def perform(category = nil)
    count = CelestrakService.refresh_if_stale(category: category.presence)

    # Enrich classified satellites with orbital analysis after fetching analyst group
    if category == "analyst" || category.blank?
      ClassifiedSatelliteEnrichmentService.enrich_all
    end

    count
  end
end
