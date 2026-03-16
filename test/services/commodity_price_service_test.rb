require "test_helper"

class CommodityPriceServiceTest < ActiveSupport::TestCase
  test "COMMODITY_MAP contains expected symbols" do
    map = CommodityPriceService::ALPHA_VANTAGE_COMMODITIES
    assert map.key?("OIL_WTI")
    assert map.key?("GOLD")
    assert map.key?("COPPER")

    map.each do |symbol, info|
      assert info.key?(:name), "#{symbol} missing :name"
      assert info.key?(:unit), "#{symbol} missing :unit"
      assert info.key?(:lat), "#{symbol} missing :lat"
      assert info.key?(:lng), "#{symbol} missing :lng"
      assert info.key?(:region), "#{symbol} missing :region"
    end
  end

  test "CURRENCY_MAP contains expected codes" do
    map = CommodityPriceService::CURRENCY_MAP
    assert map.key?("EUR")
    assert map.key?("JPY")
    assert map.key?("GBP")
  end

  test "default_commodity_price returns a price for known symbols" do
    service = CommodityPriceService.new
    assert_in_delta 72.50, service.send(:default_commodity_price, "OIL_WTI"), 0.01
    assert_in_delta 2350.00, service.send(:default_commodity_price, "GOLD"), 0.01
  end

  test "default_commodity_price returns 100.0 for unknown symbols" do
    service = CommodityPriceService.new
    assert_in_delta 100.0, service.send(:default_commodity_price, "UNKNOWN"), 0.01
  end

  test "stale? returns true when no data exists" do
    CommodityPrice.delete_all
    assert CommodityPriceService.stale?
  end

  test "stale? returns false when recent data exists" do
    CommodityPrice.create!(
      symbol: "GOLD", category: "commodity", name: "Gold",
      price: 2350.0, recorded_at: Time.current
    )
    assert_not CommodityPriceService.stale?
  end
end
