class CrossLayerAnalyzer
  module MarketSignalMethods
    private

    def chokepoint_disruptions
      chokepoints = ChokepointMonitorService.analyze rescue []

      chokepoints.filter_map do |cp|
        next if cp[:status] == "normal"
        next if cp[:conflict_pulse].empty?

        chokepoint_name = normalized_chokepoint_name(cp)
        resource_context = ResourceProfileService.for(kind: "chokepoint", identifier: cp[:id], title: chokepoint_name)
        supporting_signals = NearbySupportingSignalsService.cross_layer_signals(
          object_kind: "chokepoint",
          latitude: cp[:lat],
          longitude: cp[:lng],
          conflict_context: chokepoint_signal_conflict_context?(cp)
        )
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
          description: chokepoint_disruption_description(cp: cp, flow_parts: flow_parts, commodity_parts: commodity_parts, supporting_signals: supporting_signals, resource_context: resource_context),
          lat: cp[:lat],
          lng: cp[:lng],
          entities: {
            chokepoint: { name: chokepoint_name, status: cp[:status] },
            ships: cp[:ships_nearby],
            flows: flows.transform_values { |flow| { pct: flow[:pct], note: flow[:note] } },
            commodities: cp[:commodity_signals].first(3),
            conflict: cp[:conflict_pulse],
            supporting_signals: compact_supporting_signal_entities(supporting_signals),
            resource_context: compact_resource_context(resource_context),
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

        resource_context = ResourceProfileService.for(kind: "chokepoint", identifier: cp[:id], title: normalized_chokepoint_name(cp))
        supporting_signals = NearbySupportingSignalsService.cross_layer_signals(
          object_kind: "chokepoint",
          latitude: cp[:lat],
          longitude: cp[:lng],
          conflict_context: chokepoint_signal_conflict_context?(cp)
        )
        top_move = market_moves.max_by { |signal| signal[:change_pct].to_f.abs }
        top_pulse = Array(cp[:conflict_pulse]).max_by { |pulse| pulse[:score].to_f }
        passage_signal = chokepoint_passage_signal(cp: cp, top_move: top_move)
        market_story = chokepoint_market_story(top_move: top_move, passage_signal: passage_signal)

        {
          type: "chokepoint_market_stress",
          severity: chokepoint_market_stress_severity(cp[:status], top_move[:change_pct]),
          title: chokepoint_market_stress_title(cp: cp, top_move: top_move, market_story: market_story, passage_signal: passage_signal),
          description: chokepoint_market_stress_description(cp: cp, top_move: top_move, top_pulse: top_pulse, passage_signal: passage_signal, market_story: market_story, supporting_signals: supporting_signals, resource_context: resource_context),
          lat: cp[:lat],
          lng: cp[:lng],
          entities: {
            chokepoint: { name: normalized_chokepoint_name(cp), status: cp[:status] },
            commodities: market_moves.first(3),
            conflict: Array(cp[:conflict_pulse]).first(3),
            ships: cp[:ships_nearby],
            flows: (cp[:flows] || {}).transform_values { |flow| { pct: flow[:pct], note: flow[:note] } },
            passage_signal: compact_passage_signal_entity(passage_signal),
            supporting_signals: compact_supporting_signal_entities(supporting_signals),
            resource_context: compact_resource_context(resource_context),
          }.compact,
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

    def chokepoint_signal_conflict_context?(chokepoint)
      Array(chokepoint[:conflict_pulse]).any? do |pulse|
        pulse[:score].to_i >= 50 || %w[surging escalating active].include?(pulse[:trend].to_s)
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

    def chokepoint_disruption_description(cp:, flow_parts:, commodity_parts:, supporting_signals:, resource_context:)
      description = "#{cp[:ships_nearby][:total]} ships nearby"
      description += " (#{cp[:ships_nearby][:tankers]} tankers)" if cp[:ships_nearby][:tankers].to_i > 0
      description += " — #{flow_parts.join(", ")}" if flow_parts.any?
      description += " — #{commodity_parts.join(", ")}" if commodity_parts.any?
      description += " — #{resource_context[:summary]}" if resource_context&.dig(:summary).present?
      if (supporting = supporting_signal_summary(supporting_signals)).present?
        description += " — #{supporting}"
      end
      description
    end

    def chokepoint_market_stress_severity(status, change_pct)
      if status == "critical" || change_pct.to_f.abs >= 2.5
        "high"
      else
        "medium"
      end
    end

    def chokepoint_market_stress_title(cp:, top_move:, market_story:, passage_signal:)
      chokepoint_name = normalized_chokepoint_name(cp)

      if market_story == :relief
        "#{chokepoint_name}: #{top_move[:symbol]} falling on #{market_relief_label(passage_signal)}"
      else
        "#{chokepoint_name}: #{top_move[:symbol]} reacting to chokepoint stress"
      end
    end

    def chokepoint_market_stress_description(cp:, top_move:, top_pulse:, passage_signal:, market_story:, supporting_signals:, resource_context:)
      description_parts = [
        "#{top_move[:name] || top_move[:symbol]} #{format_change_pct(top_move[:change_pct])}",
        "#{cp.dig(:ships_nearby, :total).to_i} ships nearby",
      ]
      description_parts << "#{cp.dig(:ships_nearby, :tankers).to_i} tankers" if cp.dig(:ships_nearby, :tankers).to_i.positive?
      if market_story == :relief && passage_signal.present?
        description_parts << passage_signal_description(passage_signal)
      elsif top_pulse
        description_parts << "pulse #{top_pulse[:score]} #{top_pulse[:trend]}"
      end
      description_parts << "pulse #{top_pulse[:score]} #{top_pulse[:trend]}" if top_pulse && market_story == :relief
      description_parts << resource_context[:summary] if resource_context&.dig(:summary).present?
      description_parts << supporting_signal_summary(supporting_signals) if supporting_signals.present?
      description_parts.join(" — ")
    end

    def chokepoint_market_story(top_move:, passage_signal:)
      return :stress unless passage_signal.present?
      return :stress unless top_move[:change_pct].to_f <= -1.0
      return :stress unless relief_passage_signal?(passage_signal)

      :relief
    end

    def chokepoint_passage_signal(cp:, top_move:)
      candidates = recent_chokepoint_news(cp).filter_map do |event|
        signal = passage_signal_for_news_event(event)
        next unless signal.present?

        {
          state: signal[:state],
          signals: signal[:signals],
          excerpt: signal[:excerpt],
          headline: clean_market_signal_text(event.title.presence || event.news_article&.title),
          published_at: event.published_at,
          source_kind: event.news_source&.source_kind.to_s,
          url: event.url.presence || event.news_article&.url,
        }
      end
      return nil if candidates.empty?

      candidates.max_by do |candidate|
        [
          passage_signal_market_relevance(candidate[:state], top_move[:change_pct]),
          passage_signal_source_weight(candidate[:source_kind]),
          candidate[:published_at].to_i,
        ]
      end
    end

    def recent_chokepoint_news(chokepoint)
      name_terms = chokepoint_search_terms(chokepoint)
      spatial_scope = NewsEvent
        .where("published_at > ?", 48.hours.ago)
        .where.not(content_scope: "out_of_scope")
        .within_bounds(chokepoint_news_bounds(chokepoint))
        .includes(:news_source, :news_article)
        .order(published_at: :desc)
        .limit(18)
        .to_a

      named_scope = if name_terms.any?
        fragments = []
        bindings = {}
        name_terms.each_with_index do |term, index|
          key = :"term_#{index}"
          bindings[key] = "%#{term.downcase}%"
          fragments << "(lower(news_events.title) LIKE :#{key} OR lower(coalesce(news_articles.summary, '')) LIKE :#{key})"
        end

        NewsEvent
          .left_outer_joins(:news_article)
          .where("news_events.published_at > ?", 48.hours.ago)
          .where.not(content_scope: "out_of_scope")
          .where(fragments.join(" OR "), bindings)
          .includes(:news_source, :news_article)
          .order(published_at: :desc)
          .limit(18)
          .to_a
      else
        []
      end

      (spatial_scope + named_scope).uniq { |event| event.id }
    end

    def chokepoint_news_bounds(chokepoint)
      radius_km = [chokepoint_radius_km(chokepoint) * 3, 180].max
      bbox(chokepoint[:lat], chokepoint[:lng], radius_km)
    end

    def chokepoint_radius_km(chokepoint)
      key = chokepoint[:id].presence&.to_sym
      return ChokepointMonitorService::CHOKEPOINTS.fetch(key).fetch(:radius_km, 60) if key && ChokepointMonitorService::CHOKEPOINTS.key?(key)

      60
    end

    def chokepoint_search_terms(chokepoint)
      name = normalized_chokepoint_name(chokepoint).downcase
      terms = [name]

      terms.concat(
        case chokepoint[:id].to_s
        when "hormuz"
          ["hormuz", "strait of hormuz"]
        when "bab_el_mandeb"
          ["bab el-mandeb", "bab al-mandab", "red sea chokepoint"]
        when "malacca"
          ["malacca", "strait of malacca"]
        when "suez"
          ["suez", "suez canal"]
        when "bosphorus"
          ["bosphorus", "bosporus"]
        else
          []
        end
      )

      terms.uniq
    end

    def passage_signal_for_news_event(event)
      article = event.news_article
      persisted_signal = normalize_market_passage_signal(article&.metadata.to_h["maritime_passage_signal"])
      return persisted_signal if persisted_signal.present?

      normalize_market_passage_signal(
        MaritimePassageSignalExtractor.extract(
          title: event.title.presence || article&.title,
          summary: article&.summary
        )
      )
    end

    def normalize_market_passage_signal(signal)
      return nil unless signal.respond_to?(:[])

      state = market_signal_value_for(signal, :state).presence
      return nil if state.blank?

      {
        state: state.to_sym,
        signals: Array(market_signal_value_for(signal, :signals)).map(&:to_s),
        excerpt: clean_market_signal_text(market_signal_value_for(signal, :excerpt)),
      }
    end

    def market_signal_value_for(object, key)
      return unless object.respond_to?(:[])

      object[key] || object[key.to_s]
    end

    def clean_market_signal_text(value)
      ActionController::Base.helpers.strip_tags(value.to_s).squish.presence
    end

    def passage_signal_market_relevance(state, change_pct)
      state_name = state.to_s
      relief = %w[reopening open].include?(state_name)
      restrictive = %w[closed restricted restricted_selective].include?(state_name)

      if change_pct.to_f.negative?
        return 3 if relief
        return 2 if restrictive
      else
        return 3 if restrictive
        return 2 if relief
      end

      1
    end

    def passage_signal_source_weight(source_kind)
      {
        "wire" => 3,
        "publisher" => 2,
        "aggregator" => 1,
        "platform" => 0,
      }.fetch(source_kind.to_s, 1)
    end

    def relief_passage_signal?(passage_signal)
      %i[reopening open].include?(passage_signal[:state].to_sym)
    end

    def market_relief_label(passage_signal)
      return "safe-passage signal" if Array(passage_signal[:signals]).include?("safe_passage")

      case passage_signal[:state].to_sym
      when :open then "safe-passage signal"
      when :reopening then "reopening signal"
      else "transit signal"
      end
    end

    def passage_signal_description(passage_signal)
      state_text = if Array(passage_signal[:signals]).include?("safe_passage")
        "safe passage reported"
      else
        case passage_signal[:state].to_sym
      when :open then "safe passage reported"
      when :reopening then "reopening reported"
      when :restricted_selective then "selective passage controls reported"
      when :restricted then "transit restrictions reported"
      when :closed then "closure risk reported"
      else "passage update reported"
      end
      end
      headline = passage_signal[:headline].presence || passage_signal[:excerpt]
      headline.present? ? "#{state_text} (#{headline.truncate(120)})" : state_text
    end

    def compact_passage_signal_entity(passage_signal)
      return nil if passage_signal.blank?

      {
        state: passage_signal[:state].to_s,
        headline: passage_signal[:headline],
        excerpt: passage_signal[:excerpt],
        published_at: passage_signal[:published_at],
        url: passage_signal[:url],
      }.compact
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
