require "test_helper"

class CommodityPriceTest < ActiveSupport::TestCase
  setup do
    @now = Time.current
    @gold = CommodityPrice.create!(
      symbol: "XAU",
      category: "commodity",
      name: "Gold",
      price: 2300.50,
      change_pct: 1.2,
      unit: "USD/oz",
      latitude: 26.2,
      longitude: 28.0,
      region: "South Africa",
      recorded_at: @now,
    )
    @eur = CommodityPrice.create!(
      symbol: "EUR",
      category: "currency",
      name: "Euro",
      price: 1.08,
      change_pct: -0.3,
      unit: "USD",
      latitude: 50.1,
      longitude: 8.7,
      region: "Germany",
      recorded_at: @now,
    )
  end

  test "validates symbol presence" do
    cp = CommodityPrice.new(category: "commodity", name: "test", recorded_at: Time.current)
    assert_not cp.valid?
    assert_includes cp.errors[:symbol], "can't be blank"
  end

  test "validates category inclusion" do
    cp = CommodityPrice.new(symbol: "X", category: "invalid", name: "test", recorded_at: Time.current)
    assert_not cp.valid?
    assert_includes cp.errors[:category], "is not included in the list"
  end

  test "supports expanded market quote categories" do
    rate = CommodityPrice.new(symbol: "US10Y", category: "rate", name: "US 10Y Treasury Yield", recorded_at: Time.current)
    crypto = CommodityPrice.new(symbol: "BTCUSD", category: "crypto", name: "Bitcoin", recorded_at: Time.current)

    assert rate.valid?
    assert crypto.valid?
  end

  test "commodities scope returns only commodities" do
    results = CommodityPrice.commodities
    assert_includes results, @gold
    assert_not_includes results, @eur
  end

  test "currencies scope returns only currencies" do
    results = CommodityPrice.currencies
    assert_includes results, @eur
    assert_not_includes results, @gold
  end

  test "watchlist scope returns non-spatial quotes" do
    spy = CommodityPrice.create!(
      symbol: "SPY",
      category: "index",
      name: "US Large Caps (SPY)",
      price: 520.0,
      recorded_at: Time.current,
    )

    results = CommodityPrice.watchlist
    assert_includes results, spy
    assert_not_includes results, @gold
  end

  test "latest scope returns most recent per symbol" do
    CommodityPrice.create!(
      symbol: "XAU",
      category: "commodity",
      name: "Gold",
      price: 2290.00,
      recorded_at: 1.hour.ago,
    )

    latest = CommodityPrice.latest
    gold_latest = latest.find { |cp| cp.symbol == "XAU" }
    assert_equal 2300.50, gold_latest.price.to_f
  end
end
