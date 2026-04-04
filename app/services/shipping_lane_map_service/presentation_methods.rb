class ShippingLaneMapService
  module PresentationMethods
    private

    def build_lane(dependency:, exposures:)
      return if dependency.blank?

      prior = SupplyChainCatalog.shipping_route_prior_for(
        country_code_alpha3: dependency.country_code_alpha3,
        commodity_key: dependency.commodity_key,
        exposures: exposures
      )
      ordered_chokepoints = ordered_chokepoint_rows(exposures: exposures, prior: prior)
      primary_chokepoint = ordered_chokepoints.first

      source_anchor = source_anchor_for(dependency: dependency, primary_chokepoint: primary_chokepoint)
      destination_anchor = destination_anchor_for(
        dependency: dependency,
        near_anchor: source_anchor || chokepoint_anchor(primary_chokepoint)
      )
      waypoint_anchors = waypoint_anchors_for(
        exposures: exposures,
        ordered_chokepoints: ordered_chokepoints,
        prior: prior,
        destination_anchor: destination_anchor,
        country_code_alpha3: dependency.country_code_alpha3
      )
      destination_anchor = destination_anchor_for(
        dependency: dependency,
        near_anchor: waypoint_anchors.last || source_anchor
      )

      anchors = dedupe_anchor_sequence([source_anchor, *waypoint_anchors, destination_anchor])
      return if unresolved_lane?(anchors)
      path_points = route_points_for(anchors)

      dependency_score = dependency.dependency_score.to_f
      exposure_score = exposures.map { |row| row.exposure_score.to_f }.max.to_f
      vulnerability_score = vulnerability_score_for(
        dependency_score: dependency_score,
        exposure_score: exposure_score,
        anchor_count: anchors.size
      )

      {
        id: lane_id_for(dependency),
        type: "shipping_lane",
        name: lane_name_for(dependency: dependency, source_anchor: source_anchor),
        status: dependency.metadata["estimated"] ? "modeled" : "observed",
        commodity_key: dependency.commodity_key,
        commodity_name: dependency.commodity_name.presence || SupplyChainCatalog.commodity_name_for(dependency.commodity_key),
        commodity_flow_type: SupplyChainCatalog.commodity_flow_type_for(dependency.commodity_key).to_s,
        color: color_for(dependency.commodity_key),
        dependency_score: dependency_score.round(4),
        exposure_score: exposure_score.round(4),
        vulnerability_score: vulnerability_score.round(4),
        import_value_usd: dependency.import_value_usd&.to_f,
        import_share_gdp_pct: dependency.import_share_gdp_pct&.to_f,
        top_partner_share_pct: dependency.top_partner_share_pct&.to_f,
        supplier_count: dependency.supplier_count,
        source_country: country_hash_from_anchor(source_anchor),
        destination_country: {
          code: dependency.country_code,
          alpha3: dependency.country_code_alpha3,
          name: dependency.country_name,
        }.compact,
        source_anchor: source_anchor,
        destination_anchor: destination_anchor,
        waypoints: waypoint_anchors,
        path_points: path_points,
        chokepoints: ordered_chokepoints.first(MAX_EXPOSURES_PER_LANE).map { |row| chokepoint_summary(row) },
        top_partners: normalized_partner_breakdown(dependency),
        rationale: rationale_for(dependency: dependency, ordered_chokepoints: ordered_chokepoints),
        metadata: lane_metadata(exposures: exposures, dependency: dependency, prior: prior, path_points: path_points),
        ontology: {
          "country_node_id" => "country:#{dependency.country_code_alpha3.to_s.downcase}",
          "commodity_node_id" => "commodity:#{dependency.commodity_key}",
        },
      }
    end

    def ordered_chokepoint_rows(exposures:, prior:)
      rows_by_key = exposures.index_by(&:chokepoint_key)
      return exposures.sort_by { |row| -row.exposure_score.to_f } if prior.blank?

      primary_key = prior.fetch(:chokepoint_key).to_s
      required_keys = Array(prior[:requires_any_source_chokepoint]).map(&:to_s)
      ordered = []

      selected_source = required_keys
        .filter_map { |key| rows_by_key[key] }
        .max_by { |row| row.exposure_score.to_f }
      ordered << selected_source if selected_source.present?

      primary_row = rows_by_key[primary_key]
      ordered << primary_row if primary_row.present?

      ordered.concat(
        exposures.reject { |row| row.chokepoint_key == primary_key || required_keys.include?(row.chokepoint_key) }
          .sort_by { |row| -row.exposure_score.to_f }
      )

      ordered.uniq { |row| row.chokepoint_key }
    end

    def lane_metadata(exposures:, dependency:, prior:, path_points:)
      {
        "estimated" => dependency.metadata["estimated"] == true,
        "geometry_source" => path_points.present? ? "maritime_corridor_graph" : "anchor_geodesic_fallback",
        "support_types" => exposures.flat_map { |row| Array(row.metadata["support_types"]) }.uniq.sort,
        "route_prior" => prior&.slice(:chokepoint_key, :note),
      }
    end

    def unresolved_lane?(anchors)
      anchors.size < 2 || anchors.count { |anchor| anchor[:lat].present? && anchor[:lng].present? } < 2
    end

    def lane_id_for(dependency)
      [dependency.country_code_alpha3, dependency.commodity_key].join("-").downcase
    end

    def lane_name_for(dependency:, source_anchor:)
      source_name = source_anchor&.dig(:name).presence || dependency.top_partner_country_name.presence || "Upstream route"
      "#{source_name} to #{dependency.country_name} #{dependency.commodity_name}"
    end

    def chokepoint_summary(row)
      {
        key: row.chokepoint_key,
        name: row.chokepoint_name,
        exposure_score: row.exposure_score.to_f.round(4),
        dependency_score: row.dependency_score.to_f.round(4),
        rationale: row.rationale,
        estimated: row.metadata["estimated"] == true,
      }
    end

    def normalized_partner_breakdown(dependency)
      Array(dependency.metadata["partner_breakdown"]).first(4).map do |partner|
        {
          country_code: partner["country_code"],
          country_code_alpha3: partner["country_code_alpha3"],
          country_name: partner["country_name"],
          share_pct: partner["share_pct"],
          trade_value_usd: partner["trade_value_usd"],
        }.compact
      end
    end

    def rationale_for(dependency:, ordered_chokepoints:)
      pieces = []
      pieces << "#{dependency.country_name} shows #{dependency.commodity_name} import dependence"
      pieces << "top route pressure runs through #{ordered_chokepoints.map(&:chokepoint_name).join(' -> ')}" if ordered_chokepoints.any?
      pieces << "top supplier #{dependency.top_partner_country_name}" if dependency.top_partner_country_name.present?
      pieces.join(". ")
    end

    def vulnerability_score_for(dependency_score:, exposure_score:, anchor_count:)
      (
        (dependency_score.to_f * 0.45) +
        (exposure_score.to_f * 0.45) +
        ([anchor_count.to_i - 2, 0].max * 0.03)
      ).clamp(0.0, 1.0)
    end

    def color_for(commodity_key)
      case SupplyChainCatalog.commodity_flow_type_for(commodity_key).to_s
      when "oil" then "#ff8a00"
      when "lng" then "#26c6da"
      when "grain" then "#fbc02d"
      when "semiconductors" then "#42a5f5"
      else "#90a4ae"
      end
    end
  end
end
