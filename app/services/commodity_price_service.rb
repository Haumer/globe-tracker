require "net/http"
require "json"

class CommodityPriceService
  # Alpha Vantage symbol mapping → our internal symbols
  # Free tier: 25 calls/day — we rotate through commodities + currencies
  ALPHA_VANTAGE_COMMODITIES = {
    "OIL_WTI"   => { av_fn: "WTI",           av_interval: "daily",  name: "Crude Oil (WTI)",  unit: "USD/barrel", lat: 29.76, lng: -95.36, region: "North America" },
    "OIL_BRENT" => { av_fn: "BRENT",          av_interval: "daily",  name: "Brent Crude",      unit: "USD/barrel", lat: 57.48, lng: 1.75,   region: "North Sea" },
    "GAS_NAT"   => { av_fn: "NATURAL_GAS",    av_interval: "daily",  name: "Natural Gas",      unit: "USD/MMBtu",  lat: 29.95, lng: -90.07, region: "North America" },
    "GOLD"      => { av_fn: "GOLD",            av_interval: nil,      name: "Gold",             unit: "USD/oz",     lat: -25.75, lng: 28.23, region: "South Africa" },     # uses CURRENCY_EXCHANGE_RATE
    "SILVER"    => { av_fn: "SILVER",           av_interval: nil,      name: "Silver",           unit: "USD/oz",     lat: 23.63, lng: -102.55, region: "Mexico" },
    "COPPER"    => { av_fn: "COPPER",           av_interval: "monthly", name: "Copper",          unit: "USD/lb",     lat: -33.45, lng: -70.67, region: "Chile" },
    "WHEAT"     => { av_fn: "WHEAT",            av_interval: "daily",  name: "Wheat",            unit: "USD/bushel", lat: 41.88, lng: -87.63, region: "North America" },
    "IRON"      => { av_fn: nil,                av_interval: nil,      name: "Iron Ore",         unit: "USD/ton",    lat: -23.55, lng: -46.63, region: "Brazil" },          # no AV endpoint
    "LNG"       => { av_fn: nil,                av_interval: nil,      name: "LNG (Asia)",       unit: "USD/MMBtu",  lat: 35.68, lng: 139.69, region: "East Asia" },        # no AV endpoint
    "URANIUM"   => { av_fn: nil,                av_interval: nil,      name: "Uranium",          unit: "USD/lb",     lat: -25.27, lng: 133.78, region: "Australia" },        # no AV endpoint
  }.freeze

  CURRENCY_MAP = {
    "EUR" => { name: "Euro",              lat: 50.11, lng: 8.68,   region: "Europe" },
    "GBP" => { name: "British Pound",     lat: 51.51, lng: -0.13,  region: "UK" },
    "JPY" => { name: "Japanese Yen",      lat: 35.68, lng: 139.69, region: "Japan" },
    "CNY" => { name: "Chinese Yuan",      lat: 39.91, lng: 116.40, region: "China" },
    "CHF" => { name: "Swiss Franc",       lat: 46.95, lng: 7.45,   region: "Switzerland" },
    "AUD" => { name: "Australian Dollar", lat: -33.87, lng: 151.21, region: "Australia" },
    "CAD" => { name: "Canadian Dollar",   lat: 45.42, lng: -75.70, region: "Canada" },
    "RUB" => { name: "Russian Ruble",     lat: 55.76, lng: 37.62,  region: "Russia" },
    "INR" => { name: "Indian Rupee",      lat: 28.61, lng: 77.21,  region: "India" },
    "BRL" => { name: "Brazilian Real",    lat: -23.55, lng: -46.63, region: "Brazil" },
  }.freeze

  # Rotate: each refresh cycle fetches a subset to stay within 25 calls/day
  # Priority commodities (oil, gold, gas) fetched every cycle, others rotate
  PRIORITY_SYMBOLS = %w[OIL_WTI OIL_BRENT GAS_NAT GOLD WHEAT].freeze

  def self.refresh
    new.refresh
  end

  def self.refresh_if_stale
    return 0 if !stale?
    refresh
  end

  def self.stale?
    CommodityPrice.maximum(:recorded_at).nil? || CommodityPrice.maximum(:recorded_at) < 1.hour.ago
  end

  def refresh
    api_key = ENV["ALPHAVANTAGE_API_KEY"]
    now = Time.current
    rows = []

    # 1. ECB exchange rates (free, no key, all currencies in one call)
    rates = fetch_ecb_rates
    if rates.any?
      CURRENCY_MAP.each do |code, info|
        rate = rates[code]
        next unless rate

        prev = CommodityPrice.where(symbol: code).order(recorded_at: :desc).first
        price = (1.0 / rate).round(4)
        change_pct = prev&.price ? ((price - prev.price.to_f) / prev.price.to_f * 100).round(4) : nil

        rows << build_row(code, "currency", "#{info[:name]} (USD/#{code})", price, change_pct, "USD/#{code}", info, now)
      end
    end

    # 2. Alpha Vantage commodities (real prices)
    if api_key.present?
      # Determine which symbols to fetch this cycle (budget: ~10 calls per hour)
      cycle = (now.hour % 3) # rotate every 3 hours
      symbols_this_cycle = PRIORITY_SYMBOLS.dup
      non_priority = ALPHA_VANTAGE_COMMODITIES.keys - PRIORITY_SYMBOLS
      symbols_this_cycle.concat(non_priority.select.with_index { |_, i| i % 3 == cycle })

      symbols_this_cycle.each do |symbol|
        config = ALPHA_VANTAGE_COMMODITIES[symbol]
        next unless config[:av_fn]

        price = fetch_alpha_vantage_commodity(api_key, config)
        next unless price

        prev = CommodityPrice.where(symbol: symbol).order(recorded_at: :desc).first
        change_pct = prev&.price ? ((price - prev.price.to_f) / prev.price.to_f * 100).round(4) : nil

        rows << build_row(symbol, "commodity", config[:name], price, change_pct, config[:unit], config, now)
      end
    end

    # 3. Fallback for commodities without Alpha Vantage data
    ALPHA_VANTAGE_COMMODITIES.each do |symbol, config|
      next if rows.any? { |r| r[:symbol] == symbol }

      prev = CommodityPrice.where(symbol: symbol).order(recorded_at: :desc).first
      if prev
        # Keep last known price (no fake jitter)
        rows << build_row(symbol, "commodity", config[:name], prev.price.to_f, 0.0, config[:unit], config, now)
      else
        # First time — use default baseline
        rows << build_row(symbol, "commodity", config[:name], default_commodity_price(symbol), nil, config[:unit], config, now)
      end
    end

    CommodityPrice.upsert_all(rows, unique_by: %i[symbol recorded_at]) if rows.any?
    Rails.logger.info("CommodityPriceService: #{rows.size} prices updated")
    rows.size
  rescue => e
    Rails.logger.error("CommodityPriceService: #{e.message}")
    0
  end

  private

  def build_row(symbol, category, name, price, change_pct, unit, info, now)
    {
      symbol: symbol, category: category, name: name,
      price: price, change_pct: change_pct, unit: unit,
      latitude: info[:lat], longitude: info[:lng], region: info[:region],
      recorded_at: now,
    }
  end

  def fetch_alpha_vantage_commodity(api_key, config)
    fn = config[:av_fn]
    interval = config[:av_interval]

    if interval
      # Commodity data endpoint
      uri = URI("https://www.alphavantage.co/query?function=#{fn}&interval=#{interval}&apikey=#{api_key}")
    else
      # Precious metals use CURRENCY_EXCHANGE_RATE
      uri = URI("https://www.alphavantage.co/query?function=CURRENCY_EXCHANGE_RATE&from_currency=#{fn}&to_currency=USD&apikey=#{api_key}")
    end

    resp = Net::HTTP.get_response(uri)
    return nil unless resp.is_a?(Net::HTTPSuccess)

    data = JSON.parse(resp.body)

    # Check for rate limit
    if data["Note"] || data["Information"]
      Rails.logger.warn("Alpha Vantage rate limit: #{data["Note"] || data["Information"]}")
      return nil
    end

    if interval
      # Commodity time series: get latest data point
      series = data["data"]
      return nil unless series.is_a?(Array) && series.any?
      latest = series.first
      latest["value"]&.to_f
    else
      # Currency exchange rate
      rate = data.dig("Realtime Currency Exchange Rate", "5. Exchange Rate")
      rate&.to_f
    end
  rescue => e
    Rails.logger.warn("Alpha Vantage fetch #{config[:av_fn]}: #{e.message}")
    nil
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

    usd_rates = {}
    rates.each do |code, eur_rate|
      next if code == "USD"
      usd_rates[code] = eur_rate / eur_usd
    end
    usd_rates
  rescue => e
    Rails.logger.warn("ECB fetch failed: #{e.message}")
    {}
  end

  def default_commodity_price(symbol)
    {
      "OIL_WTI" => 72.50, "OIL_BRENT" => 76.80, "GAS_NAT" => 2.85,
      "GOLD" => 2350.00, "SILVER" => 28.50, "COPPER" => 4.15,
      "WHEAT" => 5.60, "IRON" => 110.00, "LNG" => 12.50, "URANIUM" => 85.00,
    }[symbol] || 100.0
  end
end
