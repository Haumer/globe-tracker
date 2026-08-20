# Pays the per-situation model call before anyone clicks.
#
# The layer plan's judgement fields (SituationLayerCurator: brief, radius,
# picks, regions, related) are cached on a membership fingerprint, so they only
# recompute when a situation actually changed. This job runs that computation
# in the background right after each situations build -- selecting a situation
# on the globe then reads a warm cache instead of holding the dossier open on
# a live OpenAI round-trip.
#
# Per-situation failures are logged and skipped: one bad situation must not
# leave the other seventy cold.
class WarmSituationLayersJob < ApplicationJob
  queue_as :background
  tracks_polling source: "situations:layer_warm", poll_type: "ontology"

  def perform
    # The builder just rewrote the situations; a board cached up to 2 minutes
    # ago would warm plans for rows that no longer exist.
    Rails.cache.delete("situation-board:v1:#{SituationBuilder::WINDOW_DAYS}")

    situations = SituationLayerPlanService.board[:situations] || []

    # Region resolution walks a precision ladder (district datasets, then
    # admin-1) whose fetches and point-in-polygon scans belong here, not in a
    # request: after this, /api/situations/regions and the plan service's
    # country-code fallback read warm per-anchor caches.
    begin
      anchors = situations.filter_map do |situation|
        anchor = situation[:anchor]
        anchor && { id: situation[:id], lat: anchor[:lat], lng: anchor[:lng] }
      end
      AnchorRegionService.features_for(anchors)
    rescue StandardError => error
      Rails.logger.warn("[WarmSituationLayersJob] region warm: #{error.class}: #{error.message}")
    end

    warmed = 0

    situations.each do |situation|
      SituationLayerPlanService.call(situation_id: situation[:id])
      warmed += 1
    rescue StandardError => error
      Rails.logger.warn("[WarmSituationLayersJob] situation #{situation[:id]}: #{error.class}: #{error.message}")
    end

    { records_fetched: situations.size, records_stored: warmed }
  end
end
