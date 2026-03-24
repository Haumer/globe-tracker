module Api
  class AreaReportsController < ApplicationController
    skip_before_action :authenticate_user!

    def show
      bounds = parse_bounds
      unless bounds.key?(:lamin) && bounds.key?(:lamax) && bounds.key?(:lomin) && bounds.key?(:lomax)
        return render json: { error: "Incomplete bounding box — lamin, lamax, lomin, lomax are all required" }, status: :unprocessable_entity
      end

      snapshot = AreaReportSnapshotService.fetch(bounds)
      if snapshot&.fresh?
        report = snapshot.payload
        snapshot_status = "ready"
      else
        report = snapshot&.payload.presence
        if report.blank?
          snapshot = AreaReportSnapshotService.refresh(bounds)
          report = snapshot.payload
          snapshot_status = "ready"
        else
          AreaReportSnapshotService.enqueue_refresh(bounds)
          snapshot_status = snapshot.status == "error" ? "error" : "stale"
        end
      end

      expires_in 2.minutes, public: true
      render json: report.merge(snapshot_status: snapshot_status)
    end
  end
end
