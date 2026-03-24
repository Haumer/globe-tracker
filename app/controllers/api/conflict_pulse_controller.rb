module Api
  class ConflictPulseController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      snapshot = ConflictPulseSnapshotService.fetch_or_enqueue
      data = snapshot&.payload.presence || ConflictPulseSnapshotService.empty_payload
      zones = data["zones"] || data[:zones] || []
      expires_in 5.minutes, public: true
      render json: data.merge(
        count: zones.size,
        snapshot_status: snapshot_status_for(snapshot),
      )
    end

    private

    def snapshot_status_for(snapshot)
      return "pending" unless snapshot
      return "ready" if snapshot.fresh? && snapshot.status == "ready"

      snapshot.status == "error" ? "error" : "stale"
    end
  end
end
