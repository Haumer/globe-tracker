class CrossLayerAnalyzer
  module MarketSignalMethods
    private

    def chokepoint_disruptions
      chokepoints = ChokepointMonitorService.analyze rescue []

      chokepoints.filter_map do |cp|
        next if cp[:status] == "normal"
        next if cp[:conflict_pulse].empty?

        chokepoint_name = normalized_chokepoint_name(cp)
        top_pulse = cp[:conflict_pulse].max_by { |z| z[:score] }
        commodity_parts = cp[:commodity_signals].first(3).filter_map do |signal|
          next unless signal[:change_pct] && signal[:change_pct].abs > 0.5
          "#{signal[:symbol]} #{signal[:change_pct] > 0 ? "+" : ""}#{signal[:change_pct]}%"
        end
        flows = cp[:flows] || {}
        flow_parts = flows.filter_map { |type, data| "#{data[:pct]}% of world #{type}" if data[:pct] }

        {
          type: "chokepoint_disruption",
          severity: chokepoint_disruption_severity(cp[:status]),
          title: "#{chokepoint_name}: #{top_pulse[:trend]} conflict near #{flow_parts.first || "major shipping lane"}",
          description: chokepoint_disruption_description(cp: cp, flow_parts: flow_parts, commodity_parts: commodity_parts),
          lat: cp[:lat],
          lng: cp[:lng],
          entities: {
            chokepoint: { name: chokepoint_name, status: cp[:status] },
            ships: cp[:ships_nearby],
            flows: flows.transform_values { |flow| { pct: flow[:pct], note: flow[:note] } },
            commodities: cp[:commodity_signals].first(3),
            conflict: cp[:conflict_pulse],
          },
          detected_at: cp[:checked_at],
        }
      end
    rescue => e
      Rails.logger.error("CrossLayerAnalyzer chokepoint_disruptions: #{e.message}")
      []
    end

    def chokepoint_market_stress
      chokepoints = ChokepointMonitorService.analyze rescue []
      latest_quotes = latest_market_quotes

      chokepoints.filter_map do |cp|
        market_moves = current_market_moves(cp, latest_quotes)
        next if market_moves.empty? || cp[:status] == "normal"

        top_move = market_moves.max_by { |signal| signal[:change_pct].to_f.abs }
        top_pulse = Array(cp[:conflict_pulse]).max_by { |pulse| pulse[:score].to_f }

        {
          type: "chokepoint_market_stress",
          severity: chokepoint_market_stress_severity(cp[:status], top_move[:change_pct]),
          title: "#{normalized_chokepoint_name(cp)}: #{top_move[:symbol]} reacting to chokepoint stress",
          description: chokepoint_market_stress_description(cp: cp, top_move: top_move, top_pulse: top_pulse),
          lat: cp[:lat],
          lng: cp[:lng],
          entities: {
            chokepoint: { name: normalized_chokepoint_name(cp), status: cp[:status] },
            commodities: market_moves.first(3),
            conflict: Array(cp[:conflict_pulse]).first(3),
            ships: cp[:ships_nearby],
            flows: (cp[:flows] || {}).transform_values { |flow| { pct: flow[:pct], note: flow[:note] } },
          },
          detected_at: cp[:checked_at] || Time.current.iso8601,
        }
      end
    rescue => e
      Rails.logger.error("CrossLayerAnalyzer chokepoint_market_stress: #{e.message}")
      []
    end

    def outage_currency_stress
      latest_quotes = latest_market_quotes
      latest_country_outages.filter_map do |country_code, outage|
        currency_symbol = COUNTRY_CURRENCY_MAP[country_code]
        quote = latest_quotes[currency_symbol]
        next if currency_symbol.blank? || quote.blank?
        next if quote.change_pct.blank? || quote.change_pct.to_f.abs < 0.5

        lat, lng = COUNTRY_CENTROIDS[country_code] || [nil, nil]
        traffic = InternetTrafficSnapshot.where(country_code: country_code).order(recorded_at: :desc).first

        {
          type: "outage_currency_stress",
          severity: outage_currency_stress_severity(outage: outage, quote: quote),
          title: "#{outage.entity_name}: outage coincides with #{currency_symbol} move",
          description: outage_currency_stress_description(outage: outage, traffic: traffic, currency_symbol: currency_symbol, quote: quote),
          lat: lat,
          lng: lng,
          entities: {
            outages: [{ country_code: country_code, level: outage.level, score: outage.score.to_f }],
            currency: {
              symbol: currency_symbol,
              name: quote.name,
              price: quote.price.to_f,
              change_pct: quote.change_pct.to_f,
            },
            traffic: traffic ? { country_code: traffic.country_code, traffic_pct: traffic.traffic_pct.to_f.round(1) } : nil,
          }.compact,
          detected_at: outage.started_at&.iso8601 || Time.current.iso8601,
        }
      end
    rescue => e
      Rails.logger.error("CrossLayerAnalyzer outage_currency_stress: #{e.message}")
      []
    end

    def latest_market_quotes
      YahooMarketSignalService.merge_quotes(CommodityPrice.latest.to_a).index_by(&:symbol)
    end

    def latest_country_outages
      InternetOutage.where("started_at > ?", 12.hours.ago)
        .where(entity_type: "country")
        .group_by(&:entity_code)
        .transform_values { |outages| outages.max_by { |outage| [outage.score.to_f, outage.started_at.to_i] } }
    end

    def format_change_pct(value)
      return "flat" if value.blank?

      numeric = value.to_f.round(2)
      "#{numeric.positive? ? '+' : ''}#{numeric}%"
    end

    def current_market_moves(chokepoint, latest_quotes)
      Array(chokepoint[:commodity_signals]).filter_map do |signal|
        current_quote = latest_quotes[signal[:symbol]]
        change_pct = current_quote&.change_pct&.to_f
        change_pct = signal[:change_pct].to_f if change_pct.blank?
        next if change_pct.blank? || change_pct.abs < 1.0

        signal.merge(
          name: current_quote&.name || signal[:name],
          price: current_quote&.price&.to_f&.round(2) || signal[:price],
          change_pct: change_pct.round(2)
        )
      end
    end

    def normalized_chokepoint_name(chokepoint)
      canonical_chokepoint_name(chokepoint) || fallback_chokepoint_name(chokepoint)
    end

    def canonical_chokepoint_name(chokepoint)
      key = chokepoint[:id].presence&.to_sym
      if key && ChokepointMonitorService::CHOKEPOINTS.key?(key)
        return ChokepointMonitorService::CHOKEPOINTS.fetch(key).fetch(:name)
      end

      raw_name = chokepoint[:name].to_s.squish
      exact_match = ChokepointMonitorService::CHOKEPOINTS.values.find { |candidate| candidate[:name] == raw_name }
      return exact_match[:name] if exact_match

      lat = chokepoint[:lat]
      lng = chokepoint[:lng]
      return if lat.blank? || lng.blank?

      nearby_match = ChokepointMonitorService::CHOKEPOINTS.values.find do |candidate|
        distance_km(candidate[:lat], candidate[:lng], lat, lng) <= 80
      end
      nearby_match&.fetch(:name)
    end

    def fallback_chokepoint_name(chokepoint)
      raw_name = chokepoint[:name].to_s.squish
      return "Strategic chokepoint" if raw_name.blank?
      return raw_name unless suspicious_chokepoint_name?(raw_name)

      sanitized = raw_name.split(/ carries | is a critical | makes |, making /i).first.to_s.squish
      sanitized.present? ? sanitized : "Strategic chokepoint"
    end

    def suspicious_chokepoint_name?(name)
      lowered = name.to_s.downcase
      lowered.include?("flow dependency benchmark") ||
        lowered.include?("world oil") ||
        lowered.include?("world trade") ||
        name.length > 120
    end

    def chokepoint_disruption_severity(status)
      case status
      when "critical" then "critical"
      when "elevated" then "high"
      else "medium"
      end
    end

    def chokepoint_disruption_description(cp:, flow_parts:, commodity_parts:)
      description = "#{cp[:ships_nearby][:total]} ships nearby"
      description += " (#{cp[:ships_nearby][:tankers]} tankers)" if cp[:ships_nearby][:tankers].to_i > 0
      description += " — #{flow_parts.join(", ")}" if flow_parts.any?
      description += " — #{commodity_parts.join(", ")}" if commodity_parts.any?
      description
    end

    def chokepoint_market_stress_severity(status, change_pct)
      if status == "critical" || change_pct.to_f.abs >= 2.5
        "high"
      else
        "medium"
      end
    end

    def chokepoint_market_stress_description(cp:, top_move:, top_pulse:)
      description_parts = [
        "#{top_move[:name] || top_move[:symbol]} #{format_change_pct(top_move[:change_pct])}",
        "#{cp.dig(:ships_nearby, :total).to_i} ships nearby",
      ]
      description_parts << "#{cp.dig(:ships_nearby, :tankers).to_i} tankers" if cp.dig(:ships_nearby, :tankers).to_i.positive?
      description_parts << "pulse #{top_pulse[:score]} #{top_pulse[:trend]}" if top_pulse
      description_parts.join(" — ")
    end

    def outage_currency_stress_severity(outage:, quote:)
      if outage.score.to_f >= 85 || quote.change_pct.to_f.abs >= 1.0
        "high"
      else
        "medium"
      end
    end

    def outage_currency_stress_description(outage:, traffic:, currency_symbol:, quote:)
      description = "#{outage.level} outage"
      description += ", traffic at #{traffic.traffic_pct.to_f.round(1)}% of baseline" if traffic
      description += ", #{currency_symbol} #{format_change_pct(quote.change_pct)}"
      description
    end
  end
end
