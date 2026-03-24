module Api
  class InsightsController < ApplicationController
    def index
      snapshot = InsightSnapshotService.fetch_or_enqueue
      payload = snapshot&.payload.presence || InsightSnapshotService.empty_payload
      insights = payload["insights"] || payload[:insights] || []

      render json: {
        insights: insights,
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
