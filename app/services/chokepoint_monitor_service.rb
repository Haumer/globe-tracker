class ChokepointMonitorService
  CACHE_KEY = "chokepoint_status".freeze

  # Major maritime chokepoints with trade flow data
  # Sources: EIA, UNCTAD, S&P Global, US Naval Institute
  CHOKEPOINTS = {
    hormuz: {
      name: "Strait of Hormuz",
      lat: 26.56, lng: 56.27,
      radius_km: 50,
      description: "Narrowest point ~34km. Connects Persian Gulf to Gulf of Oman.",
      flows: {
        oil: { pct: 21, volume: "20.5M barrels/day", note: "Largest oil chokepoint globally" },
        lng: { pct: 30, volume: "~5 Tcf/year", note: "Qatar is world's largest LNG exporter via Hormuz" },
        trade: { pct: nil, volume: nil, note: "Primarily energy exports — Saudi, Iraq, UAE, Kuwait, Qatar, Iran" },
      },
      countries: %w[IR OM AE SA QA KW IQ BH],
      risk_factors: ["Iran military threats", "Houthi-linked attacks", "US-Iran tensions"],
    },
    suez: {
      name: "Suez Canal",
      lat: 30.46, lng: 32.34,
      radius_km: 30,
      description: "193km canal connecting Mediterranean to Red Sea. ~19,000 transits/year.",
      flows: {
        oil: { pct: 12, volume: "9M barrels/day", note: "Europe-bound crude & refined products" },
        container: { pct: 12, volume: "~1B tons/year", note: "Asia-Europe container route" },
        trade: { pct: 15, volume: "$1T+ annually", note: "~15% of global trade by value" },
        grain: { pct: 8, volume: nil, note: "Black Sea grain exports to Asia" },
      },
      countries: %w[EG],
      risk_factors: ["Houthi Red Sea attacks", "Canal blockage (Ever Given precedent)", "Regional instability"],
    },
    malacca: {
      name: "Strait of Malacca",
      lat: 2.50, lng: 101.50,
      radius_km: 60,
      description: "Narrowest point ~2.7km at Phillips Channel. ~100,000 vessels/year.",
      flows: {
        oil: { pct: 16, volume: "16M barrels/day", note: "Middle East oil → China, Japan, South Korea" },
        container: { pct: 25, volume: nil, note: "~25% of global shipping" },
        trade: { pct: 25, volume: "$3.4T annually", note: "Most important trade route globally" },
        lng: { pct: 25, volume: nil, note: "Middle East/Australia LNG → East Asia" },
      },
      countries: %w[MY SG ID],
      risk_factors: ["Piracy", "China-Taiwan tensions could trigger blockade", "Territorial disputes"],
    },
    bab_el_mandeb: {
      name: "Bab el-Mandeb",
      lat: 12.58, lng: 43.33,
      radius_km: 30,
      description: "26km wide strait between Yemen and Djibouti/Eritrea. Gateway to Red Sea.",
      flows: {
        oil: { pct: 9, volume: "6.2M barrels/day", note: "Must-pass for Suez-bound tankers" },
        trade: { pct: 12, volume: nil, note: "Same traffic as Suez — all Suez trade passes here" },
        lng: { pct: 8, volume: nil, note: "Qatar/Oman LNG to Europe" },
      },
      countries: %w[YE DJ ER],
      risk_factors: ["Houthi attacks on shipping (active)", "Piracy from Somalia", "Yemen civil war"],
    },
    bosphorus: {
      name: "Bosphorus Strait",
      lat: 41.12, lng: 29.05,
      radius_km: 15,
      description: "31km strait through Istanbul. Only Black Sea exit. ~45,000 transits/year.",
      flows: {
        oil: { pct: 3, volume: "3M barrels/day", note: "Russian & Kazakh crude exports" },
        grain: { pct: 15, volume: "~50M tons/year", note: "Ukraine & Russia are top wheat exporters" },
        trade: { pct: nil, volume: nil, note: "Critical for Black Sea nations' trade access" },
      },
      countries: %w[TR],
      risk_factors: ["Turkey controls access (Montreux Convention)", "Russia-Ukraine war", "Grain deal disruptions"],
    },
    panama: {
      name: "Panama Canal",
      lat: 9.08, lng: -79.68,
      radius_km: 20,
      description: "82km canal connecting Atlantic to Pacific. ~14,000 transits/year.",
      flows: {
        oil: { pct: 5, volume: "~1M barrels/day", note: "US Gulf Coast → Asia" },
        container: { pct: 5, volume: nil, note: "~5% of global container trade" },
        trade: { pct: 6, volume: "$270B annually", note: "US east coast ↔ Asia-Pacific" },
        lng: { pct: 12, volume: nil, note: "US LNG exports to Asia" },
      },
      countries: %w[PA],
      risk_factors: ["Drought reducing capacity (2023-24 crisis)", "Climate change", "US-China trade tensions"],
    },
    gibraltar: {
      name: "Strait of Gibraltar",
      lat: 35.96, lng: -5.50,
      radius_km: 20,
      description: "14km wide. Only Mediterranean-Atlantic connection. ~100,000 transits/year.",
      flows: {
        oil: { pct: 5, volume: "~5M barrels/day", note: "Mediterranean refineries, North African exports" },
        trade: { pct: nil, volume: nil, note: "All Mediterranean trade exits here" },
      },
      countries: %w[ES MA GB],
      risk_factors: ["Generally stable", "Morocco-Spain tensions", "Migration routes"],
    },
    danish_straits: {
      name: "Danish Straits",
      lat: 55.70, lng: 12.60,
      radius_km: 30,
      description: "Three channels connecting Baltic to North Sea. Critical for Nordic/Baltic trade.",
      flows: {
        oil: { pct: 3, volume: "~3M barrels/day", note: "Russian crude exports (sanction-impacted)" },
        trade: { pct: nil, volume: nil, note: "Baltic states, Finland, Sweden trade access" },
      },
      countries: %w[DK SE],
      risk_factors: ["Russian sanctions enforcement", "Nord Stream sabotage precedent", "NATO-Russia tensions"],
    },
    taiwan_strait: {
      name: "Taiwan Strait",
      lat: 24.50, lng: 119.50,
      radius_km: 80,
      description: "180km wide. Separates Taiwan from mainland China.",
      flows: {
        container: { pct: 50, volume: nil, note: "~50% of global container fleet transits annually" },
        trade: { pct: 20, volume: nil, note: "~$5.3T in goods annually" },
        semiconductors: { pct: 90, volume: nil, note: "TSMC produces ~90% of advanced chips" },
      },
      countries: %w[TW CN],
      risk_factors: ["China-Taiwan military tensions", "US freedom of navigation ops", "Semiconductor supply chain"],
    },
    cape: {
      name: "Cape of Good Hope",
      lat: -34.36, lng: 18.47,
      radius_km: 100,
      description: "Southern tip of Africa. Suez alternative — adds 10-14 days to Europe-Asia route.",
      flows: {
        oil: { pct: 6, volume: nil, note: "Alternative when Suez/Red Sea disrupted" },
        trade: { pct: nil, volume: nil, note: "Surge route during Houthi Red Sea attacks" },
      },
      countries: %w[ZA],
      risk_factors: ["Weather (storms)", "Piracy (West Africa)", "Increased traffic when Red Sea disrupted"],
    },
    mozambique: {
      name: "Mozambique Channel",
      lat: -17.0, lng: 41.0,
      radius_km: 80,
      description: "1,600km long channel between Mozambique and Madagascar.",
      flows: {
        lng: { pct: 5, volume: nil, note: "Growing — TotalEnergies Mozambique LNG project" },
        trade: { pct: nil, volume: nil, note: "Alternative Cape route for some traffic" },
      },
      countries: %w[MZ MG],
      risk_factors: ["Insurgency in Cabo Delgado", "Piracy", "Climate events"],
    },
  }.freeze

  class << self
    def analyze
      Rails.cache.fetch(CACHE_KEY, expires_in: 15.minutes) { compute }
    end

    def invalidate
      Rails.cache.delete(CACHE_KEY)
    end

    private

    def compute
      CHOKEPOINTS.map do |key, cp|
        ships_nearby = count_ships_near(cp[:lat], cp[:lng], cp[:radius_km])
        conflict_pulse = nearby_conflict_pulse(cp[:lat], cp[:lng])
        commodity_signals = check_commodity_signals(key, cp)

        status = determine_status(ships_nearby, conflict_pulse, cp)

        {
          id: key.to_s,
          name: cp[:name],
          lat: cp[:lat],
          lng: cp[:lng],
          radius_km: cp[:radius_km],
          description: cp[:description],
          flows: cp[:flows],
          countries: cp[:countries],
          risk_factors: cp[:risk_factors],
          ships_nearby: ships_nearby,
          conflict_pulse: conflict_pulse,
          commodity_signals: commodity_signals,
          status: status,
          checked_at: Time.current.iso8601,
        }
      end
    end

    def count_ships_near(lat, lng, radius_km)
      return {} unless defined?(Ship)
      dlat = radius_km / 111.0
      dlng = radius_km / (111.0 * Math.cos(lat * Math::PI / 180)).abs
      bounds = { lamin: lat - dlat, lamax: lat + dlat, lomin: lng - dlng, lomax: lng + dlng }

      ships = Ship.where("updated_at > ?", 6.hours.ago).within_bounds(bounds)
      total = ships.count
      tankers = ships.where("ship_type ILIKE '%tanker%' OR ship_type ILIKE '%crude%' OR ship_type ILIKE '%oil%' OR ship_type ILIKE '%gas%' OR ship_type ILIKE '%lng%'").count rescue 0
      cargo = ships.where("ship_type ILIKE '%cargo%' OR ship_type ILIKE '%container%' OR ship_type ILIKE '%bulk%'").count rescue 0

      { total: total, tankers: tankers, cargo: cargo }
    rescue => e
      Rails.logger.warn("ChokepointMonitor ship count error: #{e.message}")
      { total: 0 }
    end

    def nearby_conflict_pulse(lat, lng)
      result = ConflictPulseService.analyze rescue {}
      zones = result.is_a?(Hash) ? (result[:zones] || []) : result
      zones.select do |z|
        dlat = (z[:lat] - lat).abs
        dlng = (z[:lng] - lng).abs
        dlat < 5 && dlng < 5 # within ~500km
      end.map { |z| { score: z[:pulse_score], trend: z[:escalation_trend] } }
    end

    def check_commodity_signals(chokepoint_key, cp)
      signals = []
      commodities = CommodityPrice.where("recorded_at > ?", 24.hours.ago)
        .order(recorded_at: :desc)

      # Map chokepoints to relevant commodities
      relevant = case chokepoint_key
        when :hormuz then %w[OIL_WTI OIL_BRENT LNG GAS_NAT]
        when :suez, :bab_el_mandeb then %w[OIL_BRENT LNG WHEAT]
        when :malacca then %w[OIL_WTI OIL_BRENT LNG]
        when :bosphorus then %w[WHEAT OIL_BRENT GAS_NAT]
        when :panama then %w[OIL_WTI LNG COPPER]
        when :taiwan_strait then %w[COPPER IRON]
        when :danish_straits then %w[OIL_BRENT GAS_NAT]
        else %w[OIL_BRENT]
      end

      relevant.each do |symbol|
        latest = commodities.find_by(symbol: symbol)
        next unless latest
        signals << {
          symbol: symbol,
          name: latest.name,
          price: latest.price.to_f.round(2),
          change_pct: latest.change_pct&.to_f&.round(2),
          flow_pct: cp.dig(:flows, :oil, :pct) || cp.dig(:flows, :lng, :pct),
        }
      end

      signals
    rescue => e
      Rails.logger.warn("ChokepointMonitor commodity error: #{e.message}")
      []
    end

    def determine_status(ships, conflict_zones, cp)
      if conflict_zones.any? { |z| z[:score] >= 70 }
        "critical"
      elsif conflict_zones.any? { |z| z[:score] >= 50 }
        "elevated"
      elsif conflict_zones.any?
        "monitoring"
      else
        "normal"
      end
    end
  end
end
