require "test_helper"

class Api::CommoditiesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_merge_quotes = YahooMarketSignalService.method(:merge_quotes)
    YahooMarketSignalService.singleton_class.send(:define_method, :merge_quotes) { |quotes| Array(quotes) }

    @now = Time.current
    CommodityPrice.create!(
      symbol: "XAU", category: "commodity", name: "Gold",
      price: 2300.50, change_pct: 1.2, unit: "USD/oz",
      latitude: 26.2, longitude: 28.0, region: "South Africa",
      recorded_at: @now,
    )
    CommodityPrice.create!(
      symbol: "EUR", category: "currency", name: "Euro",
      price: 1.08, change_pct: -0.3, unit: "USD",
      latitude: 50.1, longitude: 8.7, region: "Germany",
      recorded_at: @now,
    )
    CommodityPrice.create!(
      symbol: "SPY", category: "index", name: "US Large Caps (SPY)",
      price: 520.25, change_pct: 0.8, unit: "USD",
      region: "United States",
      recorded_at: @now,
    )
  end

  teardown do
    YahooMarketSignalService.singleton_class.send(:define_method, :merge_quotes, @original_merge_quotes)
  end

  test "GET /api/commodities returns prices" do
    get "/api/commodities"
    assert_response :success

    data = JSON.parse(response.body)
    assert_kind_of Hash, data
    assert_kind_of Array, data["prices"]
    assert_kind_of Array, data["benchmarks"]
    assert data["prices"].length >= 2
  end

  test "prices contain expected fields" do
    get "/api/commodities"
    data = JSON.parse(response.body)

    gold = data["prices"].find { |p| p["symbol"] == "XAU" }
    assert_not_nil gold
    assert_equal "commodity", gold["category"]
    assert_equal "Gold", gold["name"]
    assert_in_delta 2300.50, gold["price"], 0.01
    assert_in_delta 1.2, gold["change_pct"], 0.01
  end

  test "watchlist benchmarks are returned separately from spatial prices" do
    get "/api/commodities"
    data = JSON.parse(response.body)

    symbols = data["prices"].map { |p| p["symbol"] }
    benchmark_symbols = data["benchmarks"].map { |p| p["symbol"] }

    assert_not_includes symbols, "SPY"
    assert_includes benchmark_symbols, "SPY"
  end

  test "live yahoo signals are merged into benchmark output" do
    YahooMarketSignalService.singleton_class.send(:define_method, :merge_quotes) do |quotes|
      base_quotes = Array(quotes)
      enriched_spy = YahooMarketSignalService::Quote.new(
        symbol: "SPY",
        category: "index",
        name: "US Large Caps (SPY)",
        price: 531.10,
        change_pct: 1.4,
        unit: "USD",
        region: "United States",
        recorded_at: Time.current,
        source: "yahoo_finance",
        live_signal: true
      )
      vix_signal = YahooMarketSignalService::Quote.new(
        symbol: "VIX",
        category: "index",
        name: "CBOE Volatility Index",
        price: 18.42,
        change_pct: -2.1,
        unit: "pts",
        region: "United States",
        recorded_at: Time.current,
        source: "yahoo_finance",
        live_signal: true
      )

      base_quotes.reject { |quote| quote.symbol == "SPY" } + [enriched_spy, vix_signal]
    end

    get "/api/commodities"
    data = JSON.parse(response.body)

    spy = data["benchmarks"].find { |p| p["symbol"] == "SPY" }
    vix = data["benchmarks"].find { |p| p["symbol"] == "VIX" }

    assert_not_nil spy
    assert_equal "yahoo_finance", spy["source"]
    assert_equal true, spy["live_signal"]
    assert_in_delta 531.10, spy["price"], 0.01

    assert_not_nil vix
    assert_equal "yahoo_finance", vix["source"]
  end

  test "live spatial commodity signals stay in map prices" do
    YahooMarketSignalService.singleton_class.send(:define_method, :merge_quotes) do |quotes|
      base_quotes = Array(quotes).reject { |quote| quote.symbol == "XAU" }
      base_quotes + [
        YahooMarketSignalService::Quote.new(
          symbol: "OIL_BRENT",
          category: "commodity",
          name: "Brent Crude",
          price: 111.25,
          change_pct: 1.35,
          unit: "USD/barrel",
          latitude: 57.48,
          longitude: 1.75,
          region: "North Sea",
          recorded_at: Time.current,
          source: "yahoo_finance",
          live_signal: true
        ),
      ]
    end

    get "/api/commodities"
    data = JSON.parse(response.body)

    brent = data["prices"].find { |p| p["symbol"] == "OIL_BRENT" }

    assert_not_nil brent
    assert_in_delta 57.48, brent["lat"], 0.001
    assert_in_delta 1.75, brent["lng"], 0.001
    assert_equal "North Sea", brent["region"]
  end

  test "category filter works" do
    get "/api/commodities", params: { category: "currency" }
    data = JSON.parse(response.body)

    symbols = data["prices"].map { |p| p["symbol"] }
    assert_includes symbols, "EUR"
    assert_not_includes symbols, "XAU"
    assert_equal [], data["benchmarks"]
  end
end
