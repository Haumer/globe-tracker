require "digest"
require "set"

class RelationshipLensGraphService
  NODE_WIDTH = 156
  NODE_HEIGHT = 44
  LANE_TOP = 86
  LANE_GAP = 186
  ROW_GAP = 72
  SVG_PADDING_X = 64
  SVG_PADDING_BOTTOM = 88

  ROLE_ORDER = {
    "driver" => 0,
    "corridor" => 1,
    "flow" => 2,
    "market" => 3,
    "exposure" => 4,
    "economic_channel" => 5,
  }.freeze
  ROLE_LABELS = {
    "driver" => "Driver",
    "corridor" => "Corridor",
    "flow" => "Flow",
    "market" => "Market",
    "exposure" => "Exposure",
    "economic_channel" => "Sector",
  }.freeze
  SEVERITY_RANK = {
    "critical" => 4,
    "high" => 3,
    "medium" => 2,
    "low" => 1,
  }.freeze
  MARKET_METRIC = /\A(?:OIL_|GAS_|LNG|BRENT|WTI)/i

  class << self
    def build
      new.call
    end
  end

  def call
    chains = impact_chains
    node_index = {}
    edge_index = {}
    chain_cards = chains.map { |chain| register_chain(chain, node_index, edge_index) }

    nodes = layout_nodes(node_index.values)
    node_lookup = nodes.index_by { |node| node[:key] }

    {
      stats: stats_for(chains, node_index.values, edge_index.values),
      lanes: lane_payload,
      svg: {
        width: svg_width,
        height: svg_height(nodes),
        node_width: NODE_WIDTH,
        node_height: NODE_HEIGHT,
      },
      nodes: nodes,
      nodes_by_key: node_lookup,
      edges: edge_index.values.sort_by { |edge| [ROLE_ORDER.fetch(edge[:source_role], 99), edge[:source_label], edge[:target_label]] },
      chains: chain_cards.sort_by { |card| [-card[:score].to_i, card[:title].to_s] },
      asset_paths: live_asset_paths,
    }
  end

  private

  def impact_chains
    OntologyEntity
      .where(entity_type: %w[theater corridor country commodity])
      .find_each
      .flat_map { |node| NodeContextImpactChainService.for(node) }
      .uniq { |chain| chain[:id] }
      .sort_by { |chain| [-chain[:score].to_i, chain[:title].to_s] }
  end

  def register_chain(chain, node_index, edge_index)
    step_nodes = register_step_nodes(chain, node_index)
    market_nodes = register_market_nodes(chain, node_index)

    driver = step_nodes["driver"]
    corridor = step_nodes["corridor"]
    flow = step_nodes["flow"]
    exposure = step_nodes["exposure"]
    sector = step_nodes["economic_channel"]

    register_edge(edge_index, driver, corridor, chain) if driver && corridor
    register_edge(edge_index, corridor, flow, chain) if corridor && flow

    if market_nodes.any? && flow && exposure
      market_nodes.each do |market|
        register_edge(edge_index, flow, market, chain)
        register_edge(edge_index, market, exposure, chain)
      end
    else
      register_edge(edge_index, flow, exposure, chain) if flow && exposure
    end

    register_edge(edge_index, exposure, sector, chain) if exposure && sector

    {
      id: chain[:id],
      title: chain[:title],
      summary: chain[:summary],
      severity: chain[:severity],
      score: chain[:score],
      confidence: chain[:confidence],
      metrics: chain[:metrics] || [],
      evidence_count: Array(chain[:evidence]).size,
      path: compact_chain_path(step_nodes, market_nodes),
      node_keys: [driver, corridor, flow, *market_nodes, exposure, sector].compact.map { |node| node[:key] }.uniq,
      kind_label: driver ? "live" : "structural",
      corridor_label: corridor&.fetch(:label, nil),
    }
  end

  def register_step_nodes(chain, node_index)
    Array(chain[:steps]).each_with_object({}) do |step, result|
      role = step[:role].to_s
      next unless ROLE_ORDER.key?(role)

      key = node_key_for_step(step, role)
      result[role] = register_node(
        node_index,
        key: key,
        role: role,
        label: step[:label].presence || step.dig(:node, :name).presence || role.titleize,
        subtitle: step[:relation_type].to_s.tr("_", " "),
        canonical_key: step.dig(:node, :canonical_key),
        entity_type: step.dig(:node, :entity_type),
        chain: chain,
      )
    end
  end

  def register_market_nodes(chain, node_index)
    Array(chain[:metrics]).filter_map do |metric|
      label = metric[:label].to_s
      next unless label.match?(MARKET_METRIC)

      register_node(
        node_index,
        key: "market:#{label}",
        role: "market",
        label: label,
        subtitle: metric[:value],
        canonical_key: "market:#{label}",
        entity_type: "market_signal",
        chain: chain,
      )
    end
  end

  def register_node(node_index, key:, role:, label:, subtitle:, canonical_key:, entity_type:, chain:)
    node = node_index[key] ||= {
      id: dom_id_for(key),
      key: key,
      role: role,
      role_label: ROLE_LABELS.fetch(role),
      label: label,
      subtitle: subtitle,
      canonical_key: canonical_key,
      entity_type: entity_type,
      chain_ids: Set.new,
      chain_count: 0,
      max_score: 0,
      severity: "low",
    }

    node[:chain_ids] << chain[:id]
    node[:chain_count] = node[:chain_ids].size
    node[:max_score] = [node[:max_score].to_i, chain[:score].to_i].max
    node[:severity] = max_severity(node[:severity], chain[:severity])
    node
  end

  def register_edge(edge_index, source, target, chain)
    return if source.blank? || target.blank?

    key = "#{source[:key]}->#{target[:key]}"
    edge = edge_index[key] ||= {
      key: key,
      source_key: source[:key],
      target_key: target[:key],
      source_role: source[:role],
      target_role: target[:role],
      source_label: source[:label],
      target_label: target[:label],
      chain_ids: Set.new,
      chain_count: 0,
      max_score: 0,
      severity: "low",
    }

    edge[:chain_ids] << chain[:id]
    edge[:chain_count] = edge[:chain_ids].size
    edge[:max_score] = [edge[:max_score].to_i, chain[:score].to_i].max
    edge[:severity] = max_severity(edge[:severity], chain[:severity])
    edge
  end

  def compact_chain_path(step_nodes, market_nodes)
    [
      step_nodes["driver"],
      step_nodes["corridor"],
      step_nodes["flow"],
      market_nodes.any? ? { label: market_nodes.map { |node| node[:label] }.uniq.join(" / "), role_label: "Market" } : nil,
      step_nodes["exposure"],
      step_nodes["economic_channel"],
    ].compact.map { |node| { label: node[:label], role: node[:role_label] } }
  end

  def layout_nodes(nodes)
    grouped = nodes.group_by { |node| node[:role] }

    ROLE_ORDER.keys.flat_map do |role|
      grouped.fetch(role, [])
        .sort_by { |node| [-node[:max_score].to_i, -node[:chain_count].to_i, node[:label].to_s] }
        .each_with_index.map do |node, index|
          node.merge(
            x: lane_x(role),
            y: LANE_TOP + index * ROW_GAP,
            display_label: truncate_label(node[:label], 22),
            display_subtitle: truncate_label(node[:subtitle], 24),
          )
        end
    end
  end

  def live_asset_paths
    active = OntologyRelationship.active
      .where(source_node_type: "OntologyEntity", target_node_type: "OntologyEntity")
    pressures = active.includes(:source_node, :target_node).where(relation_type: "theater_pressure")

    pressures.flat_map do |pressure|
      active.includes(:target_node)
        .where(relation_type: "downstream_exposure", source_node: pressure.target_node)
        .map do |exposure|
          {
            driver: pressure.source_node&.canonical_name,
            corridor: pressure.target_node&.canonical_name,
            asset: exposure.target_node&.canonical_name,
            asset_type: exposure.target_node&.entity_type,
            confidence: ((pressure.confidence.to_f + exposure.confidence.to_f) / 2).round(2),
          }
        end
    end.sort_by { |row| [-row[:confidence].to_f, row[:driver].to_s, row[:corridor].to_s, row[:asset_type].to_s, row[:asset].to_s] }
  end

  def stats_for(chains, nodes, edges)
    {
      chains: chains.size,
      live_driver_chains: chains.count { |chain| Array(chain[:steps]).any? { |step| step[:role] == "driver" } },
      structural_chains: chains.count { |chain| Array(chain[:steps]).none? { |step| step[:role] == "driver" } },
      high_or_critical_chains: chains.count { |chain| %w[high critical].include?(chain[:severity]) },
      nodes: nodes.size,
      edges: edges.size,
      corridors: nodes.count { |node| node[:role] == "corridor" },
      countries: nodes.count { |node| node[:role] == "exposure" },
      markets: nodes.count { |node| node[:role] == "market" },
    }
  end

  def lane_payload
    ROLE_ORDER.map do |role, _index|
      {
        role: role,
        label: ROLE_LABELS.fetch(role),
        x: lane_x(role),
      }
    end
  end

  def lane_x(role)
    SVG_PADDING_X + NODE_WIDTH / 2 + ROLE_ORDER.fetch(role) * LANE_GAP
  end

  def svg_width
    SVG_PADDING_X * 2 + NODE_WIDTH + LANE_GAP * (ROLE_ORDER.size - 1)
  end

  def svg_height(nodes)
    max_y = nodes.map { |node| node[:y] }.max || LANE_TOP
    [520, max_y + NODE_HEIGHT / 2 + SVG_PADDING_BOTTOM].max
  end

  def node_key_for_step(step, role)
    step.dig(:node, :canonical_key).presence || "#{role}:#{step[:label]}"
  end

  def max_severity(left, right)
    SEVERITY_RANK.fetch(left.to_s, 0) >= SEVERITY_RANK.fetch(right.to_s, 0) ? left : right
  end

  def truncate_label(value, length)
    text = value.to_s.squish
    return text if text.length <= length

    "#{text.first(length - 3)}..."
  end

  def dom_id_for(key)
    "node-#{Digest::SHA256.hexdigest(key.to_s).first(12)}"
  end
end
