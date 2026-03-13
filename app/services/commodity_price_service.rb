require "net/http"
require "json"

class CommodityPriceService
  # Free data sources:
  # - ECB exchange rates (no key needed)
  # - Hardcoded commodity benchmarks with regional placement for map visualization

  # Major commodities with their production center coordinates
  COMMODITY_MAP = {
    "OIL_WTI"  => { name: "Crude Oil (WTI)", unit: "USD/barrel", lat: 29.76, lng: -95.36, region: "North America" },
    "OIL_BRENT" => { name: "Brent Crude", unit: "USD/barrel", lat: 57.48, lng: 1.75, region: "North Sea" },
    "GAS_NAT"  => { name: "Natural Gas", unit: "USD/MMBtu", lat: 29.95, lng: -90.07, region: "North America" },
    "GOLD"     => { name: "Gold", unit: "USD/oz", lat: -25.75, lng: 28.23, region: "South Africa" },
    "SILVER"   => { name: "Silver", unit: "USD/oz", lat: 23.63, lng: -102.55, region: "Mexico" },
    "COPPER"   => { name: "Copper", unit: "USD/lb", lat: -33.45, lng: -70.67, region: "Chile" },
    "WHEAT"    => { name: "Wheat", unit: "USD/bushel", lat: 41.88, lng: -87.63, region: "North America" },
    "IRON"     => { name: "Iron Ore", unit: "USD/ton", lat: -23.55, lng: -46.63, region: "Brazil" },
    "LNG"      => { name: "LNG (Asia)", unit: "USD/MMBtu", lat: 35.68, lng: 139.69, region: "East Asia" },
    "URANIUM"  => { name: "Uranium", unit: "USD/lb", lat: -25.27, lng: 133.78, region: "Australia" },
  }.freeze

  # Major currencies with representative city coordinates
  CURRENCY_MAP = {
    "EUR" => { name: "Euro", lat: 50.11, lng: 8.68, region: "Europe" },
    "GBP" => { name: "British Pound", lat: 51.51, lng: -0.13, region: "UK" },
    "JPY" => { name: "Japanese Yen", lat: 35.68, lng: 139.69, region: "Japan" },
    "CNY" => { name: "Chinese Yuan", lat: 39.91, lng: 116.40, region: "China" },
    "CHF" => { name: "Swiss Franc", lat: 46.95, lng: 7.45, region: "Switzerland" },
    "AUD" => { name: "Australian Dollar", lat: -33.87, lng: 151.21, region: "Australia" },
    "CAD" => { name: "Canadian Dollar", lat: 45.42, lng: -75.70, region: "Canada" },
    "RUB" => { name: "Russian Ruble", lat: 55.76, lng: 37.62, region: "Russia" },
    "INR" => { name: "Indian Rupee", lat: 28.61, lng: 77.21, region: "India" },
    "BRL" => { name: "Brazilian Real", lat: -23.55, lng: -46.63, region: "Brazil" },
  }.freeze

  def self.refresh
    new.refresh
  end

  def self.stale?
    CommodityPrice.maximum(:recorded_at).nil? || CommodityPrice.maximum(:recorded_at) < 1.hour.ago
  end

  def refresh
    now = Time.current
    rows = []

    # Fetch ECB exchange rates (free, no key)
    rates = fetch_ecb_rates
    if rates.any?
      CURRENCY_MAP.each do |code, info|
        rate = rates[code]
        next unless rate

        # Compute daily change (compare to previous entry)
        prev = CommodityPrice.where(symbol: code).order(recorded_at: :desc).first
        change_pct = prev&.price ? ((1.0 / rate - 1.0 / prev.price.to_f) / (1.0 / prev.price.to_f) * 100).round(4) : nil

        rows << {
          symbol: code,
          category: "currency",
          name: "#{info[:name]} (USD/#{code})",
          price: (1.0 / rate).round(4), # Store as USD per unit
          change_pct: change_pct,
          unit: "USD/#{code}",
          latitude: info[:lat],
          longitude: info[:lng],
          region: info[:region],
          recorded_at: now,
        }
      end
    end

    # Commodities: use cached/fallback static prices (a real integration would use a commodity API)
    # These serve as map anchors; actual prices would come from a paid API
    COMMODITY_MAP.each do |symbol, info|
      prev = CommodityPrice.where(symbol: symbol).order(recorded_at: :desc).first
      base_price = prev&.price&.to_f || default_commodity_price(symbol)

      # Simulate small random movement for demo (replace with real API in production)
      jitter = base_price * (rand(-0.02..0.02))
      price = (base_price + jitter).round(4)
      change_pct = base_price > 0 ? ((price - base_price) / base_price * 100).round(4) : 0

      rows << {
        symbol: symbol,
        category: "commodity",
        name: info[:name],
        price: price,
        change_pct: change_pct,
        unit: info[:unit],
        latitude: info[:lat],
        longitude: info[:lng],
        region: info[:region],
        recorded_at: now,
      }
    end

    CommodityPrice.upsert_all(rows, unique_by: %i[symbol recorded_at]) if rows.any?
    rows.size
  end

  private

  def fetch_ecb_rates
    uri = URI("https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml")
    resp = Net::HTTP.get_response(uri)
    return {} unless resp.is_a?(Net::HTTPSuccess)

    rates = {}
    # Parse XML — extract currency="XXX" rate="Y.YYYY" attributes
    resp.body.scan(/currency='(\w+)'\s+rate='([\d.]+)'/) do |code, rate|
      rates[code] = rate.to_f
    end

    # ECB rates are EUR-based. Convert to USD-based.
    eur_usd = rates["USD"]
    return {} unless eur_usd && eur_usd > 0

    usd_rates = {}
    rates.each do |code, eur_rate|
      next if code == "USD"
      usd_rates[code] = eur_rate / eur_usd # units of currency per 1 USD
    end
    usd_rates
  rescue StandardError => e
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
