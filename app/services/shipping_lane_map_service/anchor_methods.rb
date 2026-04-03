class ShippingLaneMapService
  module AnchorMethods
    private

    def source_anchor_for(dependency:, primary_chokepoint:)
      if dependency.top_partner_country_code.present?
        port_anchor_for(
          country_code: dependency.top_partner_country_code,
          country_code_alpha3: dependency.top_partner_country_code_alpha3,
          country_name: dependency.top_partner_country_name,
          commodity_key: dependency.commodity_key,
          role: :export,
          near_anchor: chokepoint_anchor(primary_chokepoint),
          estimated: false
        )
      else
        export_hub = SupplyChainCatalog.export_hub_for(
          chokepoint_key: primary_chokepoint&.chokepoint_key,
          commodity_key: dependency.commodity_key
        )
        return anchor_from_prior(export_hub, role: "load_port", estimated: true) if export_hub.present?

        chokepoint_anchor(primary_chokepoint, role: "origin_corridor")
      end
    end

    def destination_anchor_for(dependency:, near_anchor:)
      port_anchor_for(
        country_code: dependency.country_code,
        country_code_alpha3: dependency.country_code_alpha3,
        country_name: dependency.country_name,
        commodity_key: dependency.commodity_key,
        role: :import,
        near_anchor: near_anchor,
        estimated: dependency.metadata["estimated"] == true
      )
    end

    def waypoint_anchors_for(exposures:, ordered_chokepoints:, prior:, destination_anchor:, country_code_alpha3:)
      entries = []
      used_keys = {}
      used_hubs = {}
      rows_by_key = exposures.index_by(&:chokepoint_key)

      waypoint_entries = Array(prior&.dig(:route_waypoints)) +
        SupplyChainCatalog.shipping_route_extensions_for(
          destination_anchor: destination_anchor,
          country_code_alpha3: country_code_alpha3
        )

      waypoint_entries.each do |waypoint|
        if waypoint[:type].to_s == "hub"
          anchor = anchor_from_prior(waypoint, role: waypoint[:role].presence || "modeled_stopover", estimated: true)
          next if anchor.blank?

          hub_key = [anchor[:locode], anchor[:name], anchor[:country_code]]
          next if used_hubs[hub_key]

          entries << anchor
          used_hubs[hub_key] = true
        else
          row = rows_by_key[waypoint[:key].to_s]
          anchor = if row.present?
            next if used_keys[row.chokepoint_key]
            used_keys[row.chokepoint_key] = true
            chokepoint_anchor(row)
          else
            next if used_keys[waypoint[:key].to_s]
            used_keys[waypoint[:key].to_s] = true
            chokepoint_anchor_from_key(waypoint[:key], role: waypoint[:role].presence || "modeled_stopover")
          end

          entries << anchor if anchor.present?
        end
      end

      if prior.blank?
        ordered_chokepoints.each do |row|
          next if used_keys[row.chokepoint_key]

          entries << chokepoint_anchor(row)
          used_keys[row.chokepoint_key] = true
        end
      end

      entries
    end

    def dedupe_anchor_sequence(anchors)
      anchors.each_with_object([]) do |anchor, sequence|
        next if anchor.blank?
        next if sequence.any? { |existing| same_anchor?(existing, anchor) }

        sequence << anchor
      end
    end

    def same_anchor?(left, right)
      return false if left.blank? || right.blank?

      [
        left[:key].present? && right[:key].present? && left[:key] == right[:key],
        left[:locode].present? && right[:locode].present? && left[:locode] == right[:locode],
        left[:name].present? && left[:name] == right[:name] &&
          left[:country_code_alpha3].to_s == right[:country_code_alpha3].to_s,
      ].any?
    end

    def port_anchor_for(country_code:, country_code_alpha3:, country_name:, commodity_key:, role:, near_anchor:, estimated:)
      selected_anchor = best_port_anchor_for(
        country_code: country_code,
        country_code_alpha3: country_code_alpha3,
        country_name: country_name,
        commodity_key: commodity_key,
        role: role,
        near_anchor: near_anchor,
        estimated: estimated
      )
      return selected_anchor if selected_anchor.present?

      {
        kind: "country_anchor",
        role: "#{role}_country_anchor",
        name: country_name,
        country_code: country_code,
        country_code_alpha3: country_code_alpha3,
        country_name: country_name,
        estimated: true,
      }.compact
    end

    def anchor_from_trade_location(location, role:, estimated:)
      {
        kind: "port",
        role: role,
        name: location.name,
        locode: location.locode,
        country_code: location.country_code,
        country_code_alpha3: location.country_code_alpha3,
        country_name: location.country_name,
        lat: location.latitude&.to_f,
        lng: location.longitude&.to_f,
        estimated: estimated,
        source: "trade_location",
        metadata: location.metadata,
      }.compact
    end

    def anchor_from_prior(prior, role:, estimated:)
      return if prior.blank?

      if prior[:locode].present?
        location = trade_locations_by_locode[prior[:locode].to_s.upcase]
        return anchor_from_trade_location(location, role: role, estimated: estimated) if location.present?
      end

      {
        kind: prior[:kind].presence || "port",
        role: role,
        name: prior[:name],
        locode: prior[:locode],
        country_code: prior[:country_code],
        country_code_alpha3: prior[:country_code_alpha3],
        country_name: prior[:country_name],
        lat: prior[:lat],
        lng: prior[:lng],
        estimated: estimated,
        source: "prior",
        importance: prior[:importance],
        flow_types: prior[:flow_types],
        commodity_keys: prior[:commodity_keys],
        metadata: prior[:metadata] || {},
      }.compact
    end

    def chokepoint_anchor(row, role: "chokepoint")
      return if row.blank?

      config = ChokepointMonitorService::CHOKEPOINTS[row.chokepoint_key.to_sym] || {}
      {
        kind: "chokepoint",
        role: role,
        key: row.chokepoint_key,
        name: row.chokepoint_name,
        lat: config[:lat],
        lng: config[:lng],
        estimated: row.metadata["estimated"] == true,
        exposure_score: row.exposure_score.to_f.round(4),
        dependency_score: row.dependency_score.to_f.round(4),
        supplier_share_pct: row.supplier_share_pct.to_f.round(2),
      }.compact
    end

    def chokepoint_anchor_from_key(chokepoint_key, role: "chokepoint")
      config = ChokepointMonitorService::CHOKEPOINTS[chokepoint_key.to_sym]
      return if config.blank?

      {
        kind: "chokepoint",
        role: role,
        key: chokepoint_key.to_s,
        name: config[:name],
        lat: config[:lat],
        lng: config[:lng],
        estimated: true,
      }.compact
    end

    def country_hash_from_anchor(anchor)
      return {} if anchor.blank?

      {
        code: anchor[:country_code],
        alpha3: anchor[:country_code_alpha3],
        name: anchor[:country_name],
      }.compact
    end

    def distance_sq(lat_a:, lng_a:, lat_b:, lng_b:)
      ((lat_a.to_f - lat_b.to_f)**2) + ((lng_a.to_f - lng_b.to_f)**2)
    end
  end
end
