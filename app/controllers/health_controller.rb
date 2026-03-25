class HealthController < ActionController::Base
  # No auth — this endpoint is for external monitors / load balancers.

  STALENESS_THRESHOLDS = {
    "opensky"   => 60,
    "adsb"      => 60,   # matches any adsb-* source
    "usgs"      => 120,
    "gdelt"     => 120,
    "multi-news" => 120,
    "celestrak" => 300,
    "firms"     => 120,
    "ais"       => 120,
  }.freeze

  def show
    db_ok   = check_database
    poller  = check_poller
    sources = check_sources

    status = if !db_ok || %w[stopped stale].include?(poller)
               "down"
             elsif sources.values.any? { |s| s[:status] != "ok" }
               "degraded"
             else
               "healthy"
             end

    http_status = status == "down" ? 503 : 200

    render json: {
      status: status,
      timestamp: Time.current.utc.iso8601,
      database: db_ok ? "ok" : "error",
      poller: poller,
      sources: sources,
    }, status: http_status
  end

  private

  def check_database
    ActiveRecord::Base.connection.active?
  rescue
    false
  end

  def check_poller
    runtime_status = PollerRuntimeState.status
    return "paused" if runtime_status[:paused]
    return "running" if runtime_status[:running]

    runtime_status[:stale] ? "stale" : "stopped"
  end

  def check_sources
    # Grab the latest successful poll per source in one query
    latest = PollingStat
      .successful
      .where("created_at > ?", 1.hour.ago)
      .group(:source)
      .maximum(:created_at)

    now = Time.current
    results = {}

    STALENESS_THRESHOLDS.each do |key, threshold|
      # For "adsb", match any source starting with "adsb-"
      if key == "adsb"
        matching = latest.select { |src, _| src.start_with?("adsb-") }
        if matching.any?
          most_recent = matching.values.max
          age = (now - most_recent).to_i
          results[key] = source_entry(most_recent, age, threshold)
        else
          results[key] = { status: "stale", last_success: nil, age_seconds: nil }
        end
      else
        last_success = latest[key]
        if last_success
          age = (now - last_success).to_i
          results[key] = source_entry(last_success, age, threshold)
        else
          results[key] = { status: "stale", last_success: nil, age_seconds: nil }
        end
      end
    end

    results
  end

  def source_entry(last_success, age, threshold)
    {
      status: age <= threshold ? "ok" : "stale",
      last_success: last_success.utc.iso8601,
      age_seconds: age,
    }
  end
end
