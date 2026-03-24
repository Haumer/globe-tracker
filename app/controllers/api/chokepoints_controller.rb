module Api
  class ChokepointsController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      snapshot = ChokepointSnapshotService.fetch_or_enqueue
      payload = snapshot&.payload.presence || ChokepointSnapshotService.empty_payload
      chokepoints = payload["chokepoints"] || payload[:chokepoints] || []

      render json: {
        chokepoints: chokepoints,
        count: chokepoints.size,
        snapshot_status: snapshot_status_for(snapshot),
      }
    end

    private

    def snapshot_status_for(snapshot)
      return "pending" unless snapshot
      return "ready" if snapshot.fresh? && snapshot.status == "ready"

      snapshot.status == "error" ? "error" : "stale"
    end
  end
end
