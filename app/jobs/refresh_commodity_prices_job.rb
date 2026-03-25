class RefreshCommodityPricesJob < ApplicationJob
  queue_as :background
  tracks_polling source: "commodities", poll_type: "commodity_prices"

  def perform
    CommodityPriceService.refresh
  end
end
