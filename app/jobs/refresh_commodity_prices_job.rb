class RefreshCommodityPricesJob < ApplicationJob
  queue_as :default

  def perform
    CommodityPriceService.refresh
  end
end
