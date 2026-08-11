module Refreshable
  # Declare refresh config: model for timestamp, interval, and timestamp column.
  # Call once per service:
  #   refreshes model: Earthquake, interval: 5.minutes, column: :fetched_at
  #
  # Pass `scope:` when more than one service writes the model. Staleness is
  # "when did *this* service last run", and reading the whole table answers a
  # different question: a busier sibling keeps the max timestamp fresh forever
  # and this service never runs again. NewsEvent has three writers, and sitemap
  # silently starved both GDELT and RSS this way.
  def refreshes(model:, interval:, column: :fetched_at, scope: nil)
    @_refresh_model    = model
    @_refresh_interval = interval
    @_refresh_column   = column
    @_refresh_scope    = scope
  end

  def refresh_if_stale(force: false)
    return 0 if !force && !stale?
    return refresh if respond_to?(:refresh, true)

    new.refresh
  end

  def stale?
    latest_fetch_at.blank? || latest_fetch_at < @_refresh_interval.ago
  end

  def latest_fetch_at
    (@_refresh_scope&.call || @_refresh_model).maximum(@_refresh_column)
  end
end
