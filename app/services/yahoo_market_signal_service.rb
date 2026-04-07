require "cgi"

class YahooMarketSignalService
  include HttpClient

  CACHE_TTL = 60.seconds
  BASELINE_SNAPSHOT_INTERVAL = 30.minutes
  SWING_SNAPSHOT_INTERVAL = 5.minutes
  PRICE_SWING_THRESHOLD_PCT = 0.75
  CHANGE_PCT_SWING_THRESHOLD = 1.0
  USER_AGENT = "Mozilla/5.0 GlobeTracker/1.0".freeze

  Quote = Struct.new(
    :symbol,
    :category,
    :name,
    :price,
    :change_pct,
    :unit,
    :latitude,
    :longitude,
    :region,
    :recorded_at,
    :source,
    :live_signal,
    keyword_init: true
  )

  SIGNALS = {
    "VIX" => {
      yahoo_symbol: "^VIX",
      category: "index",
      name: "CBOE Volatility Index",
      unit: "pts",
      region: "United States",
      precision: 2,
    },
    "SPY" => {
      yahoo_symbol: "SPY",
      category: "index",
      name: "US Large Caps (SPY)",
      unit: "USD",
      region: "United States",
      precision: 2,
    },
    "QQQ" => {
      yahoo_symbol: "QQQ",
      category: "index",
      name: "Nasdaq 100 (QQQ)",
      unit: "USD",
      region: "United States",
      precision: 2,
    },
    "BTCUSD" => {
      yahoo_symbol: "BTC-USD",
      category: "crypto",
      name: "Bitcoin",
      unit: "USD",
      region: "Global",
      precision: 2,
    },
    "ETHUSD" => {
      yahoo_symbol: "ETH-USD",
      category: "crypto",
      name: "Ether",
      unit: "USD",
      region: "Global",
      precision: 2,
    },
    "US10Y" => {
      yahoo_symbol: "^TNX",
      category: "rate",
      name: "US 10Y Treasury Yield",
      unit: "%",
      region: "United States",
      price_scale: 0.1,
      precision: 3,
    },
    "GOLD" => {
      yahoo_symbol: "GC=F",
      category: "commodity",
      name: "Gold",
      unit: "USD/oz",
      region: "Global",
      precision: 2,
    },
    "OIL_BRENT" => {
      yahoo_symbol: "BZ=F",
      category: "commodity",
      name: "Brent Crude",
      unit: "USD/barrel",
      region: "North Sea",
      precision: 2,
    },
    "OIL_WTI" => {
      yahoo_symbol: "CL=F",
      category: "commodity",
      name: "Crude Oil (WTI)",
      unit: "USD/barrel",
      region: "North America",
      precision: 2,
    },
    "GAS_NAT" => {
      yahoo_symbol: "NG=F",
      category: "commodity",
      name: "Natural Gas",
      unit: "USD/MMBtu",
      region: "North America",
      precision: 3,
    },
  }.freeze

  class << self
    def live_quotes
      return [] if Rails.env.test?
      new.live_quotes
    end

    def merge_quotes(persisted_quotes)
      new.merge_quotes(persisted_quotes, live_quotes: live_quotes)
    end

    def persist_significant_moves(now: Time.current)
      new.persist_significant_moves(now:)
    end

    def order_symbols
      SIGNALS.keys
    end
  end

  def live_quotes
    SIGNALS.filter_map do |internal_symbol, config|
      chart = fetch_chart(config.fetch(:yahoo_symbol))
      build_quote(internal_symbol, config, chart)
    rescue StandardError => e
      Rails.logger.warn("YahooMarketSignalService #{internal_symbol}: #{e.message}")
      nil
    end
  end

  def merge_quotes(persisted_quotes, live_quotes: self.live_quotes)
    merged = Array(persisted_quotes).each_with_object({}) do |quote, memo|
      memo[quote.symbol] = quote_to_struct(quote)
    end

    Array(live_quotes).each do |live_quote|
      merged[live_quote.symbol] = merge_quote(merged[live_quote.symbol], live_quote)
    end

    merged.values
  end

  def persist_significant_moves(now: Time.current)
    current_live_quotes = live_quotes
    return { fetched: 0, stored: 0 } if current_live_quotes.empty?

    merged_quotes = merge_quotes(
      CommodityPrice.latest.where(symbol: SIGNALS.keys).to_a,
      live_quotes: current_live_quotes
    )
    live_symbols = current_live_quotes.map(&:symbol).to_set

    rows = merged_quotes.filter_map do |quote|
      next unless live_symbols.include?(quote.symbol)
      next unless should_persist_snapshot?(quote, now:)

      build_snapshot_row(quote, now)
    end

    CommodityPrice.upsert_all(rows, unique_by: %i[symbol recorded_at]) if rows.any?
    { fetched: current_live_quotes.size, stored: rows.size }
  end

  private

  def fetch_chart(yahoo_symbol)
    escaped_symbol = CGI.escape(yahoo_symbol)
    uri = URI("https://query1.finance.yahoo.com/v8/finance/chart/#{escaped_symbol}?interval=1m&range=1d&includePrePost=false")
    data = http_get(
      uri,
      headers: {
        "Accept" => "application/json",
        "User-Agent" => USER_AGENT,
      },
      open_timeout: 3,
      read_timeout: 5,
      retries: 0,
      cache_key: "http:yahoo_market_signal:#{yahoo_symbol}",
      cache_ttl: CACHE_TTL
    )

    Array(data&.dig("chart", "result"))&.first
  end

  def build_quote(internal_symbol, config, chart)
    return if chart.blank?

    meta = chart["meta"] || {}
    raw_price = meta["regularMarketPrice"] || meta["previousClose"] || meta["chartPreviousClose"]
    return if raw_price.blank?

    price = normalize_price(raw_price, config)
    previous_close = normalize_price(
      meta["regularMarketPreviousClose"] || meta["previousClose"] || meta["chartPreviousClose"],
      config
    )
    change_pct = meta["regularMarketChangePercent"]
    change_pct = percent_change(price, previous_close) if change_pct.blank?
    market_time = meta["regularMarketTime"].present? ? Time.at(meta["regularMarketTime"]).utc : Time.current
    spatial_defaults = spatial_defaults_for(internal_symbol)

    Quote.new(
      symbol: internal_symbol,
      category: config.fetch(:category),
      name: config.fetch(:name),
      price: price,
      change_pct: change_pct&.to_f&.round(2),
      unit: config.fetch(:unit),
      latitude: config[:lat] || spatial_defaults[:lat],
      longitude: config[:lng] || spatial_defaults[:lng],
      region: config[:region] || spatial_defaults[:region],
      recorded_at: market_time,
      source: "yahoo_finance",
      live_signal: true
    )
  end

  def normalize_price(value, config)
    return if value.blank?

    (value.to_f * config.fetch(:price_scale, 1.0)).round(config.fetch(:precision, 2))
  end

  def percent_change(current_value, previous_value)
    previous = previous_value.to_f
    return nil if previous.zero?

    (((current_value.to_f - previous) / previous) * 100.0).round(2)
  end

  def spatial_defaults_for(symbol)
    CommodityPriceService::SPATIAL_COMMODITIES[symbol] || {}
  end

  def quote_to_struct(quote)
    return quote if quote.is_a?(Quote)

    Quote.new(
      symbol: quote.symbol,
      category: quote.category,
      name: quote.name,
      price: quote.price&.to_f,
      change_pct: quote.change_pct&.to_f,
      unit: quote.unit,
      latitude: quote.respond_to?(:latitude) ? quote.latitude : nil,
      longitude: quote.respond_to?(:longitude) ? quote.longitude : nil,
      region: quote.region,
      recorded_at: quote.recorded_at,
      source: quote.respond_to?(:source) ? quote.source : "persisted",
      live_signal: false
    )
  end

  def merge_quote(base_quote, live_quote)
    Quote.new(
      symbol: live_quote.symbol,
      category: base_quote&.category || live_quote.category,
      name: base_quote&.name || live_quote.name,
      price: live_quote.price || base_quote&.price,
      change_pct: live_quote.change_pct.nil? ? base_quote&.change_pct : live_quote.change_pct,
      unit: base_quote&.unit || live_quote.unit,
      latitude: base_quote&.latitude || live_quote.latitude,
      longitude: base_quote&.longitude || live_quote.longitude,
      region: base_quote&.region || live_quote.region,
      recorded_at: live_quote.recorded_at || base_quote&.recorded_at,
      source: live_quote.source || base_quote&.source || "persisted",
      live_signal: live_quote.live_signal || base_quote&.live_signal || false
    )
  end

  def should_persist_snapshot?(quote, now:)
    last_snapshot = CommodityPrice.where(symbol: quote.symbol).order(recorded_at: :desc).first
    return true if last_snapshot.blank?

    elapsed = now - last_snapshot.recorded_at
    return true if elapsed >= BASELINE_SNAPSHOT_INTERVAL
    return false if elapsed < SWING_SNAPSHOT_INTERVAL

    price_move = percent_change(quote.price, last_snapshot.price)&.abs.to_f
    change_shift = if quote.change_pct.present? && last_snapshot.change_pct.present?
      (quote.change_pct.to_f - last_snapshot.change_pct.to_f).abs
    else
      0.0
    end

    price_move >= PRICE_SWING_THRESHOLD_PCT || change_shift >= CHANGE_PCT_SWING_THRESHOLD
  end

  def build_snapshot_row(quote, now)
    {
      symbol: quote.symbol,
      category: quote.category,
      name: quote.name,
      price: quote.price,
      change_pct: quote.change_pct,
      unit: quote.unit,
      latitude: quote.latitude,
      longitude: quote.longitude,
      region: quote.region,
      recorded_at: now,
      source: "yahoo_finance",
    }
  end
end
