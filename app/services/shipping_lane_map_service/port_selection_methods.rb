class ShippingLaneMapService
  module PortSelectionMethods
    private

    def best_port_anchor_for(country_code:, country_code_alpha3:, country_name:, commodity_key:, role:, near_anchor:, estimated:)
      candidate_anchors = []

      Array(trade_locations_by_country[country_code.to_s.upcase]).each do |location|
        candidate_anchors << anchor_from_trade_location(location, role: "#{role}_port", estimated: estimated)
      end

      SupplyChainCatalog.country_port_candidates_for(
        country_code: country_code,
        country_code_alpha3: country_code_alpha3,
        commodity_key: commodity_key,
        role: role
      ).each do |candidate|
        candidate_anchors << anchor_from_prior(candidate, role: "#{role}_port", estimated: true)
      end

      candidate_anchors = dedupe_anchor_sequence(candidate_anchors)
      candidate_anchors.max_by do |anchor|
        port_anchor_score(
          anchor: anchor,
          commodity_key: commodity_key,
          near_anchor: near_anchor,
          country_name: country_name
        )
      end
    end

    def port_anchor_score(anchor:, commodity_key:, near_anchor:, country_name:)
      return -Float::INFINITY if anchor.blank?

      proximity = proximity_score(anchor: anchor, near_anchor: near_anchor)
      commodity_fit = commodity_fit_score(anchor: anchor, commodity_key: commodity_key)
      basin_fit = basin_fit_score(anchor: anchor, near_anchor: near_anchor)
      importance = importance_score(anchor)
      name_bonus = anchor[:name].to_s == country_name.to_s ? 0.02 : 0.0

      (proximity * 0.32) + (commodity_fit * 0.24) + (basin_fit * 0.2) + (importance * 0.14) + name_bonus
    end

    def proximity_score(anchor:, near_anchor:)
      return 0.45 if near_anchor.blank? || near_anchor[:lat].blank? || near_anchor[:lng].blank?
      return 0.15 if anchor[:lat].blank? || anchor[:lng].blank?

      distance = Math.sqrt(distance_sq(
        lat_a: anchor[:lat],
        lng_a: anchor[:lng],
        lat_b: near_anchor[:lat],
        lng_b: near_anchor[:lng]
      ))

      (1.0 / (1.0 + distance / 20.0)).clamp(0.0, 1.0)
    end

    def commodity_fit_score(anchor:, commodity_key:)
      flow_type = SupplyChainCatalog.commodity_flow_type_for(commodity_key).to_s
      metadata = anchor[:metadata].is_a?(Hash) ? anchor[:metadata] : {}
      flow_types = Array(anchor[:flow_types] || metadata["flow_types"]).map(&:to_s)
      commodity_keys = Array(anchor[:commodity_keys] || metadata["commodity_keys"]).map(&:to_s)
      name = anchor[:name].to_s.downcase

      return 1.0 if commodity_keys.include?(commodity_key.to_s)
      return 0.95 if flow_types.include?(flow_type)
      return 0.9 if flow_type == "oil" && name.match?(/oil|energy|petro|crude|refin/i)
      return 0.88 if flow_type == "lng" && name.match?(/lng|gas/i)
      return 0.72 if %w[trade semiconductors grain].include?(flow_type)

      0.5
    end

    def basin_fit_score(anchor:, near_anchor:)
      approach_tags = approach_tags_for(near_anchor)
      return 0.45 if approach_tags.empty?

      flow_types = Array(anchor[:flow_types] || anchor.dig(:metadata, "flow_types")).map(&:to_s)
      return 1.0 if (flow_types & approach_tags).any?
      return 0.78 if flow_types.include?("trade")

      0.35
    end

    def importance_score(anchor)
      metadata = anchor[:metadata].is_a?(Hash) ? anchor[:metadata] : {}
      return anchor[:importance].to_f.clamp(0.0, 1.0) if anchor[:importance].present?

      [
        metadata["importance"],
        metadata["container_throughput_teu"],
        metadata["traffic_tons"],
        metadata["annual_tonnage"],
      ].each do |value|
        next if value.blank?

        numeric = value.to_f
        return (Math.log10([numeric, 1.0].max) / 8.0).clamp(0.1, 1.0)
      end

      case metadata["harbor_size"].to_s.downcase
      when "large", "l" then 0.9
      when "medium", "m" then 0.7
      when "small", "s" then 0.5
      else 0.55
      end
    end

    def approach_tags_for(anchor)
      return [] if anchor.blank?

      tokens = [
        anchor[:key],
        anchor[:locode],
        anchor[:name]
      ].compact.map { |value| value.to_s.downcase }

      return %w[pacific] if tokens.any? { |value| value.include?("panama") || value.include?("balboa") }
      return %w[gulf atlantic] if tokens.any? { |value| value.include?("gulf_of_mexico") || value.include?("houston") }
      return %w[atlantic] if tokens.any? { |value| value.include?("gibraltar") || value.include?("atlantic") || value.include?("channel") || value.include?("dover") || value.include?("north_sea") || value.include?("biscay") }
      return %w[indian_ocean] if tokens.any? { |value| value.include?("hormuz") || value.include?("arabian") || value.include?("colombo") || value.include?("timor") }
      return %w[pacific] if tokens.any? { |value| value.include?("malacca") || value.include?("singapore") || value.include?("china sea") || value.include?("tasman") || value.include?("coral") }

      []
    end
  end
end
