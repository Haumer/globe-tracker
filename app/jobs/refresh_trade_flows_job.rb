class RefreshTradeFlowsJob < ApplicationJob
  queue_as :background
  tracks_polling source: "strategic-trade-flows", poll_type: "trade_flows"

  def perform
    TradeFlowRefreshService.refresh_if_stale
  end
end
