class AdminController < ApplicationController
  before_action :require_admin!

  def dashboard
    @poller_status = GlobalPollerService.status

    # Recent polling stats grouped by source
    @recent_stats = PollingStat.where("created_at > ?", 1.hour.ago)
      .order(created_at: :desc)

    @stats_summary = PollingStat.where("created_at > ?", 1.hour.ago)
      .group(:source, :poll_type)
      .select(
        "source, poll_type",
        "COUNT(*) as poll_count",
        "SUM(records_fetched) as total_fetched",
        "SUM(records_stored) as total_stored",
        "AVG(duration_ms) as avg_duration",
        "COUNT(CASE WHEN status = 'error' THEN 1 END) as error_count",
        "MAX(created_at) as last_poll_at"
      )

    # Snapshot counts
    @snapshot_counts = {
      total: PositionSnapshot.count,
      last_hour: PositionSnapshot.where("recorded_at > ?", 1.hour.ago).count,
      flights_hour: PositionSnapshot.where(entity_type: "flight").where("recorded_at > ?", 1.hour.ago).count,
      ships_hour: PositionSnapshot.where(entity_type: "ship").where("recorded_at > ?", 1.hour.ago).count,
    }

    # Data freshness
    @freshness = {
      flights: Flight.maximum(:updated_at),
      ships: Ship.maximum(:updated_at),
      satellites: Satellite.maximum(:updated_at),
      earthquakes: Earthquake.maximum(:updated_at),
      news: NewsEvent.maximum(:updated_at),
      airports: Airport.maximum(:fetched_at),
    }
  end

  def toggle_poller
    if GlobalPollerService.running?
      GlobalPollerService.stop
    else
      GlobalPollerService.start
    end
    redirect_to admin_path
  end

  private

  def require_admin!
    redirect_to root_path, alert: "Not authorized" unless current_user&.admin?
  end
end
