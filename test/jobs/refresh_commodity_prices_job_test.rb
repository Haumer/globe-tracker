require "test_helper"

class RefreshCommodityPricesJobTest < ActiveSupport::TestCase
  test "is assigned to the background queue" do
    assert_equal "background", RefreshCommodityPricesJob.new.queue_name
  end

  test "tracks polling with source commodities and poll_type commodity_prices" do
    assert_equal "commodities", RefreshCommodityPricesJob.polling_source_resolver
    assert_equal "commodity_prices", RefreshCommodityPricesJob.polling_type_resolver
  end

  test "calls CommodityPriceService.refresh_if_stale" do
    called = false
    CommodityPriceService.stub(:refresh_if_stale, -> { called = true; 5 }) do
      RefreshCommodityPricesJob.perform_now
    end
    assert called
  end
end
