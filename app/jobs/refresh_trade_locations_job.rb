class RefreshTradeLocationsJob < ApplicationJob
  queue_as :background
  tracks_polling source: "trade-locations", poll_type: "trade_locations"

  def perform
    TradeLocationRefreshService.refresh_if_stale
  end
end
