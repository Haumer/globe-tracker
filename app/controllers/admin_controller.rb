class AdminController < ApplicationController
  before_action :require_admin!

  def api_health
    window = params[:window].to_i
    window = 1 if window <= 0 || window > 24
    since = window.hours.ago

    # Preload all stats for the window to avoid N+1
    all_stats = PollingStat.where("created_at > ?", since).to_a
    stats_by_source = all_stats.group_by(&:source)

    # Preload last records per source (most recent 5 for consecutive error check)
    all_sources = PollingStat.distinct.pluck(:source).sort

    @window = window
    @sources = all_sources.map do |source|
      source_stats = stats_by_source[source] || []
      total = source_stats.size
      errors = source_stats.count { |s| s.status == "error" }
      successes = total - errors

      # Sort once for reuse
      sorted_desc = source_stats.sort_by { |s| -s.created_at.to_i }
      success_stats = sorted_desc.select { |s| s.status == "success" }

      last_success = PollingStat.where(source: source, status: "success").order(created_at: :desc).first
      last_error = PollingStat.where(source: source, status: "error").order(created_at: :desc).first
      last_poll = PollingStat.where(source: source).order(created_at: :desc).first

      avg_duration = success_stats.any? ? (success_stats.sum(&:duration_ms) / success_stats.size.to_f).round : 0
      sorted_durations = success_stats.map(&:duration_ms).sort
      p95_duration = sorted_durations.any? ? sorted_durations[(sorted_durations.size * 0.95).floor] || 0 : 0
      avg_fetched = success_stats.any? ? (success_stats.sum(&:records_fetched) / success_stats.size.to_f).round : 0

      # Determine health status
      status = if total == 0
        :unknown
      elsif last_poll && last_poll.status == "error" && last_error &&
            (last_success.nil? || last_error.created_at > last_success.created_at)
        consecutive_errors = PollingStat.where(source: source)
          .order(created_at: :desc).limit(5).pluck(:status).take_while { |s| s == "error" }.size
        consecutive_errors >= 3 ? :down : :degraded
      elsif errors > 0 && total > 0 && (errors.to_f / total) > 0.3
        :degraded
      else
        :healthy
      end

      # Sparkline data: success/error counts per bucket
      bucket_minutes = window <= 1 ? 5 : (window <= 6 ? 15 : 30)
      sparkline = source_stats
        .group_by { |s| s.created_at.beginning_of_hour + (s.created_at.min / bucket_minutes * bucket_minutes).minutes }
        .sort_by(&:first)
        .map { |t, rows| { t: t.strftime("%H:%M"), ok: rows.count { |r| r.status == "success" }, err: rows.count { |r| r.status == "error" } } }

      # Recent errors (last 5)
      recent_errors = PollingStat.where(source: source, status: "error")
        .order(created_at: :desc).limit(5)
        .pluck(:created_at, :error_message, :duration_ms)
        .map { |t, msg, dur| { time: t, message: msg, duration: dur } }

      {
        source: source,
        poll_type: last_poll&.poll_type || "unknown",
        status: status,
        total: total,
        successes: successes,
        errors: errors,
        success_rate: total > 0 ? ((successes.to_f / total) * 100).round(1) : 0,
        avg_duration: avg_duration,
        p95_duration: p95_duration,
        avg_fetched: avg_fetched,
        last_success_at: last_success&.created_at,
        last_error_at: last_error&.created_at,
        last_poll_at: last_poll&.created_at,
        last_error_message: last_error&.error_message,
        sparkline: sparkline,
        recent_errors: recent_errors,
      }
    end

    # Summary counts
    @summary = {
      total: @sources.size,
      healthy: @sources.count { |s| s[:status] == :healthy },
      degraded: @sources.count { |s| s[:status] == :degraded },
      down: @sources.count { |s| s[:status] == :down },
      unknown: @sources.count { |s| s[:status] == :unknown },
    }
  end

  def dashboard
    @poller_status = PollerRuntimeState.status

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

    @feed_statuses = SourceFeedStatus.active_first.limit(24)

    # Snapshot counts (use estimated total to avoid slow full-table count)
    estimated_total = ActiveRecord::Base.connection.execute(
      "SELECT reltuples::bigint FROM pg_class WHERE relname = 'position_snapshots'"
    ).first&.fetch("reltuples", 0) || 0

    @snapshot_counts = {
      total: estimated_total,
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
      natural_events: NaturalEvent.maximum(:updated_at),
      conflict_events: ConflictEvent.maximum(:updated_at),
      internet_outages: InternetOutage.maximum(:updated_at),
      airports: Airport.maximum(:fetched_at),
      commodities: CommodityPrice.maximum(:recorded_at),
      weather_alerts: WeatherAlert.maximum(:fetched_at),
      notams: Notam.maximum(:fetched_at),
    }

    # API usage tracking
    @api_usage = {
      alpha_vantage: { calls_today: Rails.cache.read("av_calls_today") || 0, daily_limit: 20 },
      openai: { key_set: ENV["OPENAI_API_KEY"].present? },
      news_enriched: NewsEvent.where(ai_enriched: true).where("published_at > ?", 24.hours.ago).count,
      news_unenriched: NewsEvent.where(ai_enriched: [nil, false]).where("published_at > ?", 48.hours.ago).count,
    }
  end

  def toggle_poller
    status = PollerRuntimeState.status
    if status[:running] || status[:paused]
      PollerRuntimeState.request_stop!
      flash[:notice] = "Stopped the dedicated poller process."
    else
      PollerRuntimeState.ensure_running!
      flash[:notice] = "Enabled the dedicated poller process. Ensure the Heroku poller dyno is scaled."
    end
    redirect_to admin_path
  end

  def pause_poller
    if PollerRuntimeState.status[:paused]
      PollerRuntimeState.request_resume!
      flash[:notice] = "Resumed dedicated polling."
    else
      PollerRuntimeState.request_pause!
      flash[:notice] = "Paused dedicated polling."
    end
    redirect_to admin_path
  end

  def stop_poller
    PollerRuntimeState.request_stop!
    flash[:notice] = "Stopped the dedicated poller process."
    redirect_to admin_path
  end

  private

  def require_admin!
    redirect_to root_path, alert: "Not authorized" unless current_user&.admin?
  end
end
