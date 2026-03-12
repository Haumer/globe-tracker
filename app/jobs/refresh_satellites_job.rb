class RefreshSatellitesJob < ApplicationJob
  queue_as :default

  def perform(category = nil)
    CelestrakService.refresh_if_stale(category: category.presence)

    # Enrich classified satellites with orbital analysis after fetching analyst group
    if category == "analyst" || category.blank?
      ClassifiedSatelliteEnrichmentService.enrich_all
    end
  end
end
