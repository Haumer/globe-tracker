module Refreshable
  # Declare refresh config: model for timestamp, interval, and timestamp column.
  # Call once per service:
  #   refreshes model: Earthquake, interval: 5.minutes, column: :fetched_at
  def refreshes(model:, interval:, column: :fetched_at)
    @_refresh_model    = model
    @_refresh_interval = interval
    @_refresh_column   = column
  end

  def refresh_if_stale(force: false)
    return 0 if !force && !stale?
    new.refresh
  end

  def stale?
    latest_fetch_at.blank? || latest_fetch_at < @_refresh_interval.ago
  end

  def latest_fetch_at
    @_refresh_model.maximum(@_refresh_column)
  end
end
