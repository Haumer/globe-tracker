require "test_helper"

class YahooMarketSignalServiceTest < ActiveSupport::TestCase
  setup do
    Rails.cache.clear
  end

  test "live_quotes normalizes yahoo chart data" do
    stub_request(:get, %r{\Ahttps://query1\.finance\.yahoo\.com/v8/finance/chart/}).to_return do |request|
      encoded_symbol = request.uri.path.split("/").last
      yahoo_symbol = CGI.unescape(encoded_symbol)

      body = case yahoo_symbol
      when "SPY"
        yahoo_chart_body(price: 531.10, previous_close: 524.00, market_time: 1_711_700_000)
      when "^VIX"
        yahoo_chart_body(price: 18.42, previous_close: 19.10, market_time: 1_711_700_010)
      when "^TNX"
        yahoo_chart_body(price: 42.71, previous_close: 42.11, market_time: 1_711_700_020)
      else
        { chart: { result: [], error: nil } }.to_json
      end

      { status: 200, body: body, headers: { "Content-Type" => "application/json" } }
    end

    quotes = YahooMarketSignalService.new.live_quotes

    spy = quotes.find { |quote| quote.symbol == "SPY" }
    vix = quotes.find { |quote| quote.symbol == "VIX" }
    us10y = quotes.find { |quote| quote.symbol == "US10Y" }

    assert_not_nil spy
    assert_equal "yahoo_finance", spy.source
    assert_equal true, spy.live_signal
    assert_in_delta 531.10, spy.price, 0.01
    assert_in_delta 1.35, spy.change_pct, 0.01

    assert_not_nil vix
    assert_equal "pts", vix.unit

    assert_not_nil us10y
    assert_in_delta 4.271, us10y.price, 0.001
  end

  test "merge_quotes overlays live signal fields and preserves spatial metadata" do
    CommodityPrice.create!(
      symbol: "GOLD",
      category: "commodity",
      name: "Gold",
      price: 2300.50,
      change_pct: 1.2,
      unit: "USD/oz",
      latitude: 26.2,
      longitude: 28.0,
      region: "South Africa",
      recorded_at: Time.current - 10.minutes,
    )

    original_live_quotes = YahooMarketSignalService.method(:live_quotes)
    YahooMarketSignalService.singleton_class.send(:define_method, :live_quotes) do
      [
        YahooMarketSignalService::Quote.new(
          symbol: "GOLD",
          category: "commodity",
          name: "Gold",
          price: 2345.10,
          change_pct: 2.4,
          unit: "USD/oz",
          region: "Global",
          recorded_at: Time.current,
          source: "yahoo_finance",
          live_signal: true
        ),
      ]
    end

    merged = YahooMarketSignalService.merge_quotes(CommodityPrice.latest.to_a)
    gold = merged.find { |quote| quote.symbol == "GOLD" }

    assert_not_nil gold
    assert_in_delta 2345.10, gold.price, 0.01
    assert_equal 26.2, gold.latitude
    assert_equal 28.0, gold.longitude
    assert_equal "South Africa", gold.region
    assert_equal "yahoo_finance", gold.source
  ensure
    YahooMarketSignalService.singleton_class.send(:define_method, :live_quotes, original_live_quotes)
  end

  test "persist_significant_moves stores first live snapshot" do
    service = YahooMarketSignalService.new
    live_quote = YahooMarketSignalService::Quote.new(
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

    service.define_singleton_method(:live_quotes) { [live_quote] }
    result = service.persist_significant_moves(now: Time.current)

    persisted = CommodityPrice.where(symbol: "VIX").order(recorded_at: :desc).first

    assert_equal 1, result[:stored]
    assert_not_nil persisted
    assert_equal "yahoo_finance", persisted.source
  end

  test "persist_significant_moves skips small moves inside baseline interval" do
    CommodityPrice.create!(
      symbol: "VIX",
      category: "index",
      name: "CBOE Volatility Index",
      price: 18.40,
      change_pct: -2.0,
      unit: "pts",
      region: "United States",
      recorded_at: 10.minutes.ago,
      source: "yahoo_finance"
    )
    service = YahooMarketSignalService.new
    live_quote = YahooMarketSignalService::Quote.new(
      symbol: "VIX",
      category: "index",
      name: "CBOE Volatility Index",
      price: 18.45,
      change_pct: -2.2,
      unit: "pts",
      region: "United States",
      recorded_at: Time.current,
      source: "yahoo_finance",
      live_signal: true
    )

    service.define_singleton_method(:live_quotes) { [live_quote] }
    result = service.persist_significant_moves(now: Time.current)

    assert_equal 0, result[:stored]
    assert_equal 1, CommodityPrice.where(symbol: "VIX").count
  end

  test "persist_significant_moves stores big swings faster" do
    CommodityPrice.create!(
      symbol: "VIX",
      category: "index",
      name: "CBOE Volatility Index",
      price: 18.40,
      change_pct: -2.0,
      unit: "pts",
      region: "United States",
      recorded_at: 6.minutes.ago,
      source: "yahoo_finance"
    )
    service = YahooMarketSignalService.new
    live_quote = YahooMarketSignalService::Quote.new(
      symbol: "VIX",
      category: "index",
      name: "CBOE Volatility Index",
      price: 19.10,
      change_pct: 2.2,
      unit: "pts",
      region: "United States",
      recorded_at: Time.current,
      source: "yahoo_finance",
      live_signal: true
    )

    service.define_singleton_method(:live_quotes) { [live_quote] }
    result = service.persist_significant_moves(now: Time.current)

    assert_equal 1, result[:stored]
    assert_equal 2, CommodityPrice.where(symbol: "VIX").count
  end

  private

  def yahoo_chart_body(price:, previous_close:, market_time:)
    {
      chart: {
        result: [
          {
            meta: {
              regularMarketPrice: price,
              regularMarketPreviousClose: previous_close,
              regularMarketTime: market_time,
            },
          },
        ],
        error: nil,
      },
    }.to_json
  end
end
