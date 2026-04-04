class PortMapService
  MAX_PORTS = 800
  MAX_COUNTRY_DEPENDENCY_HINTS = 3

  class << self
    def ports(limit: MAX_PORTS)
      new(limit: limit).ports
    end
  end

  def initialize(limit:)
    @limit = limit
  end

  def ports
    merged = {}

    observed_ports.each do |location|
      merge_port!(merged, port_from_trade_location(location))
    end

    catalog_port_candidates.each do |candidate|
      merge_port!(merged, port_from_candidate(candidate))
    end

    merged.values
      .filter_map { |port| enrich_port(port) }
      .sort_by { |port| [-port.fetch(:importance_score).to_f, port[:estimated] ? 1 : 0, port.fetch(:name)] }
      .first(@limit)
  end

  private

  def observed_ports
    TradeLocation.active
      .where(location_kind: "port")
      .where.not(latitude: nil, longitude: nil)
      .order(:country_code, :name)
  end

  def catalog_port_candidates
    SupplyChainCatalog.all_country_port_candidates
  end

  def merge_port!(index, incoming)
    return if incoming.blank?

    key = port_key(incoming)
    index[key] = if index[key].present?
      merge_port(index[key], incoming)
    else
      incoming
    end
  end

  def merge_port(existing, incoming)
    {
      id: existing[:id] || incoming[:id],
      locode: existing[:locode] || incoming[:locode],
      name: existing[:name] || incoming[:name],
      country_code: existing[:country_code] || incoming[:country_code],
      country_code_alpha3: existing[:country_code_alpha3] || incoming[:country_code_alpha3],
      country_name: existing[:country_name] || incoming[:country_name],
      lat: existing[:lat] || incoming[:lat],
      lng: existing[:lng] || incoming[:lng],
      estimated: existing[:estimated] && incoming[:estimated],
      source: [existing[:source], incoming[:source]].compact.uniq.join("+"),
      importance_score: [existing[:importance_score], incoming[:importance_score]].compact.max.to_f,
      flow_types: (Array(existing[:flow_types]) + Array(incoming[:flow_types])).map(&:to_s).uniq,
      commodity_keys: (Array(existing[:commodity_keys]) + Array(incoming[:commodity_keys])).map(&:to_s).uniq,
      roles: (Array(existing[:roles]) + Array(incoming[:roles])).map(&:to_s).uniq,
      metadata: (existing[:metadata].is_a?(Hash) ? existing[:metadata] : {}).merge(
        incoming[:metadata].is_a?(Hash) ? incoming[:metadata] : {}
      ),
    }.compact
  end

  def port_from_trade_location(location)
    metadata = location.metadata.is_a?(Hash) ? location.metadata : {}

    {
      id: port_identifier(locode: location.locode, country_code: location.country_code, name: location.name),
      locode: location.locode,
      name: location.name,
      country_code: location.country_code,
      country_code_alpha3: location.country_code_alpha3,
      country_name: location.country_name,
      lat: location.latitude&.to_f,
      lng: location.longitude&.to_f,
      estimated: false,
      source: location.source,
      importance_score: importance_score_for(metadata: metadata),
      flow_types: Array(metadata["flow_types"]).map(&:to_s),
      commodity_keys: Array(metadata["commodity_keys"]).map(&:to_s),
      roles: ["trade_gateway"],
      metadata: metadata.slice("harbor_size", "function_codes", "status", "importance", "traffic_tons", "annual_tonnage", "container_throughput_teu"),
    }.compact
  end

  def port_from_candidate(candidate)
    flow_types = Array(candidate[:flow_types]).map(&:to_s)
    commodity_keys = [candidate[:candidate_commodity_key], *SupplyChainCatalog.commodity_keys_for_flow_types(flow_types)].compact.map(&:to_s).uniq

    {
      id: port_identifier(locode: candidate[:locode], country_code: candidate[:country_code], name: candidate[:name]),
      locode: candidate[:locode],
      name: candidate[:name],
      country_code: candidate[:country_code],
      country_code_alpha3: candidate[:country_code_alpha3],
      country_name: candidate[:country_name],
      lat: candidate[:lat]&.to_f,
      lng: candidate[:lng]&.to_f,
      estimated: true,
      source: "catalog_prior",
      importance_score: candidate[:importance].to_f.nonzero? || 0.55,
      flow_types: flow_types,
      commodity_keys: commodity_keys,
      roles: [candidate[:role]].compact,
      metadata: {},
    }.compact
  end

  def enrich_port(port)
    return if port[:lat].blank? || port[:lng].blank?

    country_dependencies = country_dependencies_for(port)
    explicit_keys = Array(port[:commodity_keys]).map(&:to_s)
    flow_type_keys = SupplyChainCatalog.commodity_keys_for_flow_types(port[:flow_types])

    dependency_keys = if explicit_keys.empty? || generic_trade_port?(port)
      country_dependencies.first(MAX_COUNTRY_DEPENDENCY_HINTS).map(&:commodity_key)
    else
      []
    end

    estimated_keys = (explicit_keys + flow_type_keys + dependency_keys).uniq.first(5)
    estimated_names = estimated_keys.filter_map { |key| SupplyChainCatalog.commodity_name_for(key) }

    primary_flow_type = select_primary_flow_type(port, estimated_keys)

    port.merge(
      primary_flow_type: primary_flow_type,
      estimated_commodity_keys: estimated_keys,
      estimated_commodity_names: estimated_names,
      country_dependency_commodities: country_dependencies.first(MAX_COUNTRY_DEPENDENCY_HINTS).filter_map { |row|
        SupplyChainCatalog.commodity_name_for(row.commodity_key)
      },
      map_label: map_label_for(port),
      place_label: place_label_for(port),
      importance_tier: importance_tier_for(port[:importance_score]),
    )
  end

  def generic_trade_port?(port)
    flow_types = Array(port[:flow_types]).map(&:to_s)
    flow_types.empty? || (flow_types - %w[trade container atlantic pacific gulf indian_ocean]).empty?
  end

  def select_primary_flow_type(port, estimated_keys)
    flow_types = Array(port[:flow_types]).map(&:to_s)

    return "oil" if flow_types.include?("oil")
    return "lng" if flow_types.include?("lng")
    return "semiconductors" if flow_types.include?("semiconductors")
    return "grain" if flow_types.include?("grain")

    inferred_flow_type = Array(estimated_keys).filter_map do |key|
      SupplyChainCatalog.commodity_flow_type_for(key)
    end.first

    return inferred_flow_type.to_s if inferred_flow_type.present?

    return "trade"
  end

  def importance_tier_for(score)
    value = score.to_f
    return "global" if value >= 0.88
    return "regional" if value >= 0.72
    return "national" if value >= 0.56

    "local"
  end

  def importance_score_for(metadata:)
    return metadata["importance"].to_f.clamp(0.0, 1.0) if metadata["importance"].present?

    %w[container_throughput_teu traffic_tons annual_tonnage].each do |key|
      next if metadata[key].blank?

      numeric = metadata[key].to_f
      return (Math.log10([numeric, 1.0].max) / 8.0).clamp(0.1, 1.0)
    end

    case metadata["harbor_size"].to_s.downcase
    when "large", "l" then 0.82
    when "medium", "m" then 0.66
    when "small", "s" then 0.52
    else 0.5
    end
  end

  def map_label_for(port)
    parts = [port[:name].presence, place_label_for(port)]
    parts.compact.join(", ")
  end

  def place_label_for(port)
    port[:country_code].presence ||
      port[:country_code_alpha3].presence ||
      port[:country_name].presence
  end

  def country_dependencies_by_alpha3
    @country_dependencies_by_alpha3 ||= CountryCommodityDependency
      .order(dependency_score: :desc)
      .to_a
      .group_by(&:country_code_alpha3)
  end

  def country_dependencies_by_iso2
    @country_dependencies_by_iso2 ||= CountryCommodityDependency
      .order(dependency_score: :desc)
      .to_a
      .group_by(&:country_code)
  end

  def country_dependencies_for(port)
    alpha3 = port[:country_code_alpha3].to_s.upcase
    code = port[:country_code].to_s.upcase

    Array(country_dependencies_by_alpha3[alpha3]).presence ||
      Array(country_dependencies_by_iso2[code])
  end

  def port_key(port)
    port[:locode].presence&.to_s&.upcase ||
      [port[:country_code].to_s.upcase, port[:name].to_s.downcase.gsub(/[^a-z0-9]+/, "-")].join(":")
  end

  def port_identifier(locode:, country_code:, name:)
    token = locode.presence || "#{country_code.to_s.upcase}-#{name.to_s.downcase.gsub(/[^a-z0-9]+/, "-")}"
    token.to_s.downcase
  end
end
