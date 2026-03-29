require "net/http"
require "json"
require "set"

class CommodityPriceService
  # Spatially-anchored quotes that belong on the globe.
  SPATIAL_COMMODITIES = {
    "OIL_WTI"   => { av_fn: "WTI",          av_interval: "daily",   name: "Crude Oil (WTI)", unit: "USD/barrel", lat: 29.76, lng: -95.36, region: "North America" },
    "OIL_BRENT" => { av_fn: "BRENT",        av_interval: "daily",   name: "Brent Crude",     unit: "USD/barrel", lat: 57.48, lng: 1.75,   region: "North Sea" },
    "GAS_NAT"   => { av_fn: "NATURAL_GAS",  av_interval: "daily",   name: "Natural Gas",     unit: "USD/MMBtu",  lat: 29.95, lng: -90.07, region: "North America" },
    "GOLD"      => { av_fn: "GOLD",         av_interval: nil,       name: "Gold",            unit: "USD/oz",     lat: -25.75, lng: 28.23, region: "South Africa" },
    "SILVER"    => { av_fn: "SILVER",       av_interval: nil,       name: "Silver",          unit: "USD/oz",     lat: 23.63, lng: -102.55, region: "Mexico" },
    "COPPER"    => { av_fn: "COPPER",       av_interval: "monthly", name: "Copper",          unit: "USD/lb",     lat: -33.45, lng: -70.67, region: "Chile" },
    "WHEAT"     => { av_fn: "WHEAT",        av_interval: "daily",   name: "Wheat",           unit: "USD/bushel", lat: 41.88, lng: -87.63, region: "North America" },
    "IRON"      => { av_fn: nil,            av_interval: nil,       name: "Iron Ore",        unit: "USD/ton",    lat: -23.55, lng: -46.63, region: "Brazil" },
    "LNG"       => { av_fn: nil,            av_interval: nil,       name: "LNG (Asia)",      unit: "USD/MMBtu",  lat: 35.68, lng: 139.69, region: "East Asia" },
    "URANIUM"   => { av_fn: nil,            av_interval: nil,       name: "Uranium",         unit: "USD/lb",     lat: -25.27, lng: 133.78, region: "Australia" },
  }.freeze

  # Backward-compatible constant name used by tests.
  ALPHA_VANTAGE_COMMODITIES = SPATIAL_COMMODITIES

  CURRENCY_MAP = {
    "EUR" => { name: "Euro",              lat: 50.11, lng: 8.68,    region: "Europe" },
    "GBP" => { name: "British Pound",     lat: 51.51, lng: -0.13,   region: "UK" },
    "JPY" => { name: "Japanese Yen",      lat: 35.68, lng: 139.69,  region: "Japan" },
    "CNY" => { name: "Chinese Yuan",      lat: 39.91, lng: 116.40,  region: "China" },
    "CHF" => { name: "Swiss Franc",       lat: 46.95, lng: 7.45,    region: "Switzerland" },
    "AUD" => { name: "Australian Dollar", lat: -33.87, lng: 151.21, region: "Australia" },
    "CAD" => { name: "Canadian Dollar",   lat: 45.42, lng: -75.70,  region: "Canada" },
    "RUB" => { name: "Russian Ruble",     lat: 55.76, lng: 37.62,   region: "Russia" },
    "INR" => { name: "Indian Rupee",      lat: 28.61, lng: 77.21,   region: "India" },
    "BRL" => { name: "Brazilian Real",    lat: -23.55, lng: -46.63, region: "Brazil" },
  }.freeze

  # Non-spatial market watchlist. These quotes should inform insights and
  # watchlists, not become fake globe markers.
  MARKET_BENCHMARKS = {
    "SPY" => {
      category: "index",
      av_kind: :global_quote,
      av_symbol: "SPY",
      name: "US Large Caps (SPY)",
      unit: "USD",
      region: "United States",
    },
    "QQQ" => {
      category: "index",
      av_kind: :global_quote,
      av_symbol: "QQQ",
      name: "Nasdaq 100 (QQQ)",
      unit: "USD",
      region: "United States",
    },
    "BTCUSD" => {
      category: "crypto",
      av_kind: :exchange_rate,
      from_currency: "BTC",
      to_currency: "USD",
      name: "Bitcoin",
      unit: "USD",
      region: "Global",
    },
    "ETHUSD" => {
      category: "crypto",
      av_kind: :exchange_rate,
      from_currency: "ETH",
      to_currency: "USD",
      name: "Ether",
      unit: "USD",
      region: "Global",
    },
    "US2Y" => {
      category: "rate",
      av_kind: :economic_indicator,
      av_function: "TREASURY_YIELD",
      interval: "daily",
      maturity: "2year",
      name: "US 2Y Treasury Yield",
      unit: "%",
      region: "United States",
    },
    "US10Y" => {
      category: "rate",
      av_kind: :economic_indicator,
      av_function: "TREASURY_YIELD",
      interval: "daily",
      maturity: "10year",
      name: "US 10Y Treasury Yield",
      unit: "%",
      region: "United States",
    },
    "FEDFUNDS" => {
      category: "rate",
      av_kind: :economic_indicator,
      av_function: "FEDERAL_FUNDS_RATE",
      interval: "daily",
      name: "US Federal Funds Rate",
      unit: "%",
      region: "United States",
    },
  }.freeze

  WATCHLIST_SYMBOLS = MARKET_BENCHMARKS.keys.freeze
  PRIORITY_ALPHA_VANTAGE_SYMBOLS = %w[OIL_BRENT GOLD BTCUSD US10Y].freeze
  DAILY_CALL_LIMIT = 20
  REFRESH_INTERVAL = 6.hours

  class << self
    def refresh
      new.refresh
    end

    def refresh_if_stale
      return 0 unless stale?
      refresh
    end

    def stale?
      snapshot_scope = CommodityPrice.where("source IS NULL OR source != ?", "yahoo_finance")
      snapshot_scope.maximum(:recorded_at).nil? || snapshot_scope.maximum(:recorded_at) < REFRESH_INTERVAL.ago
    end
  end

  def refresh
    api_key = ENV["ALPHAVANTAGE_API_KEY"]
    now = Time.current
    rows = []

    rows.concat(build_currency_rows(now))
    rows.concat(build_alpha_vantage_rows(api_key, now)) if api_key.present?
    rows.concat(build_fallback_rows(now, rows.map { |row| row[:symbol] }.to_set))

    CommodityPrice.upsert_all(rows, unique_by: %i[symbol recorded_at]) if rows.any?
    Rails.logger.info("CommodityPriceService: #{rows.size} quotes updated")
    rows.size
  rescue => e
    Rails.logger.error("CommodityPriceService: #{e.message}")
    0
  end

  private

  def build_currency_rows(now)
    rates = fetch_ecb_rates
    return [] if rates.empty?

    CURRENCY_MAP.each_with_object([]) do |(code, info), rows|
      rate = rates[code]
      next unless rate

      prev = latest_record_for(code)
      price = (1.0 / rate).round(4)
      change_pct = percent_change(price, prev&.price)

      rows << build_row(code, "currency", "#{info[:name]} (USD/#{code})", price, change_pct, "USD/#{code}", info, now, source: "ecb")
    end
  end

  def build_alpha_vantage_rows(api_key, now)
    av_calls_today = alpha_vantage_calls_today

    alpha_vantage_symbols_for_cycle(now).each_with_object([]) do |symbol, rows|
      break rows if av_calls_today >= DAILY_CALL_LIMIT

      config = alpha_vantage_registry.fetch(symbol)
      quote = fetch_alpha_vantage_quote(api_key, config)
      av_calls_today += 1
      persist_alpha_vantage_calls_today(av_calls_today)
      next unless quote&.dig(:price)

      prev = latest_record_for(symbol)
      change_pct = quote[:change_pct]
      change_pct = percent_change(quote[:price], prev&.price) if change_pct.nil?

      rows << build_row(
        symbol,
        config.fetch(:category),
        config.fetch(:name),
        quote.fetch(:price),
        change_pct,
        config.fetch(:unit),
        config,
        now,
        source: "alpha_vantage"
      )
    end
  end

  def build_fallback_rows(now, built_symbols)
    fallback_configs.each_with_object([]) do |(symbol, payload), rows|
      next if built_symbols.include?(symbol)

      config = payload.fetch(:config)
      prev = latest_record_for(symbol)
      if prev
        rows << build_row(symbol, payload.fetch(:category), config.fetch(:name), prev.price.to_f, 0.0, config.fetch(:unit), config, now, source: "fallback")
      else
        rows << build_row(symbol, payload.fetch(:category), config.fetch(:name), payload.fetch(:default_price), nil, config.fetch(:unit), config, now, source: "fallback")
      end
    end
  end

  def fallback_configs
    commodity_payloads = SPATIAL_COMMODITIES.transform_values do |config|
      { config: config, category: "commodity", default_price: default_commodity_price(config) }
    end
    benchmark_payloads = MARKET_BENCHMARKS.transform_values do |config|
      { config: config, category: config.fetch(:category), default_price: default_benchmark_price(config) }
    end

    commodity_payloads.merge(benchmark_payloads)
  end

  def alpha_vantage_registry
    @alpha_vantage_registry ||= begin
      commodity_payload = SPATIAL_COMMODITIES.each_with_object({}) do |(symbol, config), memo|
        next unless config[:av_fn]

        av_kind = config[:av_interval].present? ? :commodity_series : :exchange_rate
        memo[symbol] = config.merge(
          category: "commodity",
          av_kind: av_kind,
          from_currency: config[:av_fn],
          to_currency: "USD",
        )
      end

      commodity_payload.merge(MARKET_BENCHMARKS)
    end
  end

  def alpha_vantage_symbols_for_cycle(now)
    all_symbols = alpha_vantage_registry.keys
    priority = PRIORITY_ALPHA_VANTAGE_SYMBOLS & all_symbols
    rotating = all_symbols - priority
    rotating_slots = [(DAILY_CALL_LIMIT / cycles_per_day) - priority.size, 0].max
    return priority if rotating_slots.zero? || rotating.empty?

    cycle_index = (now.to_i / REFRESH_INTERVAL.to_i).floor
    start_index = (cycle_index * rotating_slots) % rotating.size
    rotating_symbols = cycling_slice(rotating, start_index, rotating_slots)

    priority + rotating_symbols
  end

  def cycles_per_day
    @cycles_per_day ||= (24.hours.to_i / REFRESH_INTERVAL.to_i)
  end

  def cycling_slice(items, start_index, size)
    return [] if size <= 0 || items.empty?

    Array.new(size) { |offset| items[(start_index + offset) % items.length] }
  end

  def alpha_vantage_calls_today
    cached_date = Rails.cache.read("av_call_date")
    if cached_date != Date.current.to_s
      Rails.cache.write("av_call_date", Date.current.to_s, expires_in: 2.days)
      Rails.cache.write("av_calls_today", 0, expires_in: 2.days)
      return 0
    end

    Rails.cache.read("av_calls_today").to_i
  end

  def persist_alpha_vantage_calls_today(value)
    Rails.cache.write("av_call_date", Date.current.to_s, expires_in: 2.days)
    Rails.cache.write("av_calls_today", value, expires_in: 2.days)
  end

  def latest_record_for(symbol)
    CommodityPrice.where(symbol: symbol).order(recorded_at: :desc).first
  end

  def build_row(symbol, category, name, price, change_pct, unit, info, now, source:)
    {
      symbol: symbol,
      category: category,
      name: name,
      price: price,
      change_pct: change_pct,
      unit: unit,
      latitude: info[:lat],
      longitude: info[:lng],
      region: info[:region],
      recorded_at: now,
      source: source,
    }
  end

  def percent_change(current_value, previous_value)
    previous = previous_value.to_f
    return nil if previous.zero?

    (((current_value.to_f - previous) / previous) * 100).round(4)
  end

  def fetch_alpha_vantage_quote(api_key, config)
    case config[:av_kind]
    when :commodity_series
      fetch_alpha_vantage_commodity_series(api_key, config)
    when :exchange_rate
      fetch_alpha_vantage_exchange_rate(api_key, config.fetch(:from_currency), config.fetch(:to_currency, "USD"))
    when :global_quote
      fetch_alpha_vantage_global_quote(api_key, config.fetch(:av_symbol))
    when :economic_indicator
      fetch_alpha_vantage_economic_indicator(api_key, config)
    end
  rescue => e
    Rails.logger.warn("CommodityPriceService Alpha Vantage fetch failed for #{config[:name]}: #{e.message}")
    nil
  end

  def fetch_alpha_vantage_commodity_series(api_key, config)
    uri = URI("https://www.alphavantage.co/query?function=#{config[:av_fn]}&interval=#{config[:av_interval]}&apikey=#{api_key}")
    data = fetch_json(uri)
    return nil unless data
    return nil if rate_limited_response?(data)

    latest = Array(data["data"]).first
    price = latest&.dig("value")&.to_f
    return nil unless price

    { price: price }
  end

  def fetch_alpha_vantage_exchange_rate(api_key, from_currency, to_currency)
    uri = URI("https://www.alphavantage.co/query?function=CURRENCY_EXCHANGE_RATE&from_currency=#{from_currency}&to_currency=#{to_currency}&apikey=#{api_key}")
    data = fetch_json(uri)
    return nil unless data
    return nil if rate_limited_response?(data)

    rate = data.dig("Realtime Currency Exchange Rate", "5. Exchange Rate")&.to_f
    return nil unless rate

    { price: rate }
  end

  def fetch_alpha_vantage_global_quote(api_key, symbol)
    uri = URI("https://www.alphavantage.co/query?function=GLOBAL_QUOTE&symbol=#{symbol}&apikey=#{api_key}")
    data = fetch_json(uri)
    return nil unless data
    return nil if rate_limited_response?(data)

    quote = data["Global Quote"] || {}
    price = quote["05. price"]&.to_f
    change_pct = quote["10. change percent"]&.delete("%")&.to_f
    return nil unless price

    { price: price, change_pct: change_pct }
  end

  def fetch_alpha_vantage_economic_indicator(api_key, config)
    query = {
      function: config.fetch(:av_function),
      interval: config.fetch(:interval, "daily"),
      apikey: api_key,
    }
    query[:maturity] = config[:maturity] if config[:maturity].present?

    uri = URI("https://www.alphavantage.co/query?#{URI.encode_www_form(query)}")
    data = fetch_json(uri)
    return nil unless data
    return nil if rate_limited_response?(data)

    latest = Array(data["data"]).find { |row| row["value"].present? && row["value"] != "." }
    price = latest&.dig("value")&.to_f
    return nil unless price

    { price: price }
  end

  def fetch_json(uri)
    resp = Net::HTTP.get_response(uri)
    return nil unless resp.is_a?(Net::HTTPSuccess)

    JSON.parse(resp.body)
  end

  def rate_limited_response?(data)
    if data["Note"] || data["Information"]
      Rails.logger.warn("Alpha Vantage rate limit: #{data["Note"] || data["Information"]}")
      return true
    end

    false
  end

  def fetch_ecb_rates
    uri = URI("https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml")
    resp = Net::HTTP.get_response(uri)
    return {} unless resp.is_a?(Net::HTTPSuccess)

    rates = {}
    resp.body.scan(/currency='(\w+)'\s+rate='([\d.]+)'/) do |code, rate|
      rates[code] = rate.to_f
    end

    eur_usd = rates["USD"]
    return {} unless eur_usd && eur_usd > 0

    rates.each_with_object({}) do |(code, eur_rate), usd_rates|
      next if code == "USD"
      usd_rates[code] = eur_rate / eur_usd
    end
  rescue => e
    Rails.logger.warn("ECB fetch failed: #{e.message}")
    {}
  end

  def default_commodity_price(config_or_symbol)
    config = config_or_symbol.is_a?(Hash) ? config_or_symbol : SPATIAL_COMMODITIES[config_or_symbol]
    name = config&.fetch(:name, nil)
    {
      "Crude Oil (WTI)" => 72.50,
      "Brent Crude" => 76.80,
      "Natural Gas" => 2.85,
      "Gold" => 2350.00,
      "Silver" => 28.50,
      "Copper" => 4.15,
      "Wheat" => 5.60,
      "Iron Ore" => 110.00,
      "LNG (Asia)" => 12.50,
      "Uranium" => 85.00,
    }[name] || 100.0
  end

  def default_benchmark_price(config_or_symbol)
    config = config_or_symbol.is_a?(Hash) ? config_or_symbol : MARKET_BENCHMARKS[config_or_symbol]
    name = config&.fetch(:name, nil)
    {
      "US Large Caps (SPY)" => 520.0,
      "Nasdaq 100 (QQQ)" => 445.0,
      "Bitcoin" => 65000.0,
      "Ether" => 3400.0,
      "US 2Y Treasury Yield" => 4.35,
      "US 10Y Treasury Yield" => 4.15,
      "US Federal Funds Rate" => 5.25,
    }[name] || 100.0
  end
end
