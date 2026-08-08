module Api
  class FireClustersController < ApplicationController
    skip_before_action :authenticate_user!

    # A real day yields ~25,000 clusters, so this is a runaway guard rather than
    # a working limit -- set below that it would silently drop live fires. For
    # discrete rendering ask for `notable` (~1,500 major+extreme); the long tail
    # of single-pixel minors belongs in a density layer, not as map pins.
    MAX_CLUSTERS = 60_000

    def index
      clusters = FireCluster.all
      clusters = clusters.by_tier(params[:tier]) if params[:tier].present?
      clusters = clusters.notable if params[:notable].present?
      clusters = clusters.within_bounds(bounds_param) if bounds_param

      # Ordering by intensity means a client that does cap the list keeps the
      # fires that matter, rather than an arbitrary slice like the raw hotspot
      # endpoint's `limit(5000)` -- which only ever showed the most recent ~1.2
      # hours of a 24-hour feed.
      clusters = clusters.strongest.limit(limit_param)

      render json: clusters.map { |cluster|
        [
          cluster.external_id,
          cluster.latitude,
          cluster.longitude,
          cluster.intensity_mw,
          cluster.tier,
          cluster.pixel_count,
          cluster.pass_count,
          cluster.last_detected_at&.to_i&.*(1000),
          cluster.first_detected_at&.to_i&.*(1000),
          cluster.latest_mw,
        ]
      }
    end

    # The evolution of one fire: every satellite pass that saw it, in order.
    # This is the graph payload -- p99 is 6 points, so it stays small.
    def show
      cluster = FireCluster.find_by!(external_id: params[:id])

      render json: {
        id: cluster.external_id,
        latitude: cluster.latitude,
        longitude: cluster.longitude,
        tier: cluster.tier,
        intensity_mw: cluster.intensity_mw,
        latest_mw: cluster.latest_mw,
        trend: cluster.trend,
        pixel_count: cluster.pixel_count,
        pass_count: cluster.pass_count,
        detection_count: cluster.detection_count,
        satellites: cluster.satellites,
        first_detected_at: cluster.first_detected_at,
        last_detected_at: cluster.last_detected_at,
        observations: cluster.series,
      }
    end

    private

    # The globe caps how many pins it will draw, so let it say so rather than
    # download 25,000 rows and throw most away. Ordering is by intensity, so a
    # capped response is the strongest fires, not an arbitrary slice.
    def limit_param
      requested = params[:limit].to_i
      return MAX_CLUSTERS unless requested.positive?

      [requested, MAX_CLUSTERS].min
    end

    def bounds_param
      return nil unless %i[lamin lamax lomin lomax].all? { |key| params[key].present? }

      {
        lamin: params[:lamin].to_f, lamax: params[:lamax].to_f,
        lomin: params[:lomin].to_f, lomax: params[:lomax].to_f,
      }
    end
  end
end
