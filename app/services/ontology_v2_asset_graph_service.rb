class OntologyV2AssetGraphService
  DERIVED_BY = "ontology_v2_asset_graph_v1".freeze
  LOCATED_IN_COUNTRY = "located_in_country".freeze
  LANDS_IN_COUNTRY = "lands_in_country".freeze
  ASSET_ENTITY_TYPES = {
    airport: "airport",
    military_base: "military_base",
    port: "port",
    power_plant: "power_plant",
    submarine_cable: "submarine_cable",
  }.freeze
  BATCH_TARGETS = %w[airports military_bases power_plants ports submarine_cables].freeze
  INFERRED_COUNTRY_CONFIDENCE = 0.72
  INFERRED_CABLE_COUNTRY_CONFIDENCE = 0.68
  BASE_COUNTRY_INFERENCE_RADIUS_KM = 80.0
  CABLE_COUNTRY_INFERENCE_RADIUS_KM = 75.0

  class << self
    def sync(now: Time.current)
      new(now: now).sync
    end

    def sync_batch(target:, cursor: nil, batch_size: 500, now: Time.current)
      new(now: now).sync_batch(target: target, cursor: cursor, batch_size: batch_size)
    end

    def health_report
      new.health_report
    end
  end

  def initialize(now: Time.current)
    @now = now
  end

  def sync
    result = {
      assets: 0,
      country_relationships: 0,
    }

    ActiveRecord::Base.transaction do
      result[:country_relationships] += sync_airports
      result[:country_relationships] += sync_military_bases
      result[:country_relationships] += sync_power_plants
      result[:country_relationships] += sync_ports
      result[:country_relationships] += sync_submarine_cables
      result[:assets] = asset_scope.count
      result[:health] = health_report
    end

    result
  end

  def sync_batch(target:, cursor: nil, batch_size: 500)
    target = target.to_s
    raise ArgumentError, "unknown asset graph batch target: #{target}" unless BATCH_TARGETS.include?(target)

    limit = batch_size.to_i.clamp(1, 5_000)
    records = batch_scope_for(target)
    records = records.where("#{records.klass.table_name}.id > ?", cursor.to_i) if cursor.present?
    records = records.order(:id).limit(limit).to_a
    stored = 0

    ActiveRecord::Base.transaction do
      stored = records.sum { |record| sync_record_for_target(target, record) }
    end

    {
      target: target,
      cursor: cursor,
      next_cursor: records.size < limit ? nil : records.last&.id,
      records_fetched: records.size,
      records_stored: stored,
      complete: records.size < limit,
    }
  end

  def health_report
    linked_asset_ids = country_relationship_scope.pluck(:source_node_id).index_with(true)
    assets = asset_scope.to_a

    {
      assets: assets.size,
      country_relationships: country_relationship_scope.count,
      unlocated_assets: assets.reject { |asset| linked_asset_ids[asset.id] }.first(50).map do |asset|
        {
          id: asset.id,
          canonical_key: asset.canonical_key,
          entity_type: asset.entity_type,
          canonical_name: asset.canonical_name,
          country_code: asset.country_code,
          country_code_alpha3: asset.metadata["country_code_alpha3"],
          country_name: asset.metadata["country_name"],
        }.compact
      end,
    }
  end

  private

  attr_reader :now

  def sync_airports
    Airport.find_each.sum { |airport| sync_airport(airport) }
  end

  def sync_military_bases
    MilitaryBase.find_each.sum { |base| sync_military_base(base) }
  end

  def sync_power_plants
    PowerPlant.find_each.sum { |plant| sync_power_plant(plant) }
  end

  def sync_ports
    port_scope.find_each.sum { |port| sync_port(port) }
  end

  def sync_submarine_cables
    SubmarineCable.find_each.sum { |cable| sync_submarine_cable(cable) }
  end

  def sync_airport(airport)
    entity = upsert_asset_entity(
      canonical_key: "airport:#{airport.icao_code.to_s.downcase}",
      entity_type: ASSET_ENTITY_TYPES.fetch(:airport),
      canonical_name: airport.name,
      country_code: airport.country_code,
      metadata: {
        "airport_type" => airport.airport_type,
        "iata_code" => airport.iata_code,
        "icao_code" => airport.icao_code,
        "municipality" => airport.municipality,
        "latitude" => airport.latitude,
        "longitude" => airport.longitude,
        "is_military" => airport.is_military,
      }.compact,
      linkable: airport,
      link_role: airport.is_military? ? "military_airport" : "airport",
      aliases: { "official" => airport.name, "icao" => airport.icao_code, "iata" => airport.iata_code }
    )
    link_asset_country(entity, country_codes: [airport.country_code], country_names: [])
  end

  def sync_military_base(base)
    country_refs = military_base_country_refs(base)
    entity = upsert_asset_entity(
      canonical_key: "military-base:#{base.external_id}",
      entity_type: ASSET_ENTITY_TYPES.fetch(:military_base),
      canonical_name: base.name.presence || base.external_id,
      country_code: iso_like_code(country_refs.fetch(:codes).first || base.country),
      metadata: {
        "base_type" => base.base_type,
        "operator" => base.operator,
        "country" => base.country,
        "latitude" => base.latitude,
        "longitude" => base.longitude,
        "source" => base.source,
      }.merge(country_refs.fetch(:metadata)).compact,
      linkable: base,
      link_role: "military_base",
      aliases: { "official" => base.name, "external_id" => base.external_id }
    )
    link_asset_country(
      entity,
      country_codes: country_refs.fetch(:codes),
      country_names: country_refs.fetch(:names),
      confidence: country_refs.fetch(:confidence)
    )
  end

  def sync_power_plant(plant)
    entity = upsert_asset_entity(
      canonical_key: "power-plant:#{plant.gppd_idnr.to_s.downcase}",
      entity_type: ASSET_ENTITY_TYPES.fetch(:power_plant),
      canonical_name: plant.name,
      country_code: plant.country_code,
      metadata: {
        "primary_fuel" => plant.primary_fuel,
        "capacity_mw" => plant.capacity_mw,
        "owner" => plant.owner,
        "latitude" => plant.latitude,
        "longitude" => plant.longitude,
        "country_name" => plant.country_name,
      }.compact,
      linkable: plant,
      link_role: "power_plant",
      aliases: { "official" => plant.name, "external_id" => plant.gppd_idnr }
    )
    link_asset_country(entity, country_codes: [plant.country_code], country_names: [plant.country_name])
  end

  def sync_port(port)
    metadata = port.metadata.is_a?(Hash) ? port.metadata : {}
    entity = upsert_asset_entity(
      canonical_key: "port:#{port.locode.to_s.downcase}",
      entity_type: ASSET_ENTITY_TYPES.fetch(:port),
      canonical_name: port.name,
      country_code: port.country_code,
      metadata: {
        "locode" => port.locode,
        "country_code_alpha3" => port.country_code_alpha3,
        "country_name" => port.country_name,
        "function_codes" => port.function_codes,
        "latitude" => port.latitude,
        "longitude" => port.longitude,
        "flow_types" => Array(metadata["flow_types"]),
        "harbor_size" => metadata["harbor_size"],
        "importance" => metadata["importance"],
        "source" => port.source,
      }.compact,
      linkable: port,
      link_role: "port",
      aliases: { "official" => port.name, "locode" => port.locode }
    )
    link_asset_country(entity, country_codes: [port.country_code, port.country_code_alpha3], country_names: [port.country_name])
  end

  def sync_submarine_cable(cable)
    country_refs = cable_country_refs(cable)
    entity = upsert_asset_entity(
      canonical_key: "submarine-cable:#{cable.cable_id}",
      entity_type: ASSET_ENTITY_TYPES.fetch(:submarine_cable),
      canonical_name: cable.name.presence || cable.cable_id,
      metadata: {
        "color" => cable.color,
        "landing_point_count" => Array(cable.landing_points).size,
        "country_codes" => country_refs.fetch(:codes).presence,
        "country_names" => country_refs.fetch(:names).presence,
      }.merge(country_refs.fetch(:metadata)).compact,
      linkable: cable,
      link_role: "submarine_cable",
      aliases: { "official" => cable.name, "external_id" => cable.cable_id }
    )
    link_asset_country(
      entity,
      country_codes: country_refs.fetch(:codes),
      country_names: country_refs.fetch(:names),
      relation_type: LANDS_IN_COUNTRY,
      confidence: country_refs.fetch(:confidence)
    )
  end

  def upsert_asset_entity(canonical_key:, entity_type:, canonical_name:, metadata:, linkable:, link_role:, aliases:, country_code: nil)
    OntologySyncSupport.upsert_entity(
      canonical_key: canonical_key,
      entity_type: entity_type,
      canonical_name: canonical_name,
      country_code: country_code,
      metadata: metadata.merge("asset_graph_synced_at" => now.iso8601)
    ).tap do |entity|
      aliases.each do |alias_type, value|
        OntologySyncSupport.upsert_alias(entity, value, alias_type: alias_type) if value.present?
      end
      OntologySyncSupport.upsert_link(entity, linkable, role: link_role, method: DERIVED_BY)
    end
  end

  def link_asset_country(entity, country_codes:, country_names:, relation_type: LOCATED_IN_COUNTRY, confidence: 0.88)
    countries = resolve_countries(country_codes: country_codes, country_names: country_names)
    delete_stale_country_links(entity, relation_type: relation_type, keep_country_ids: countries.map(&:id))

    countries.count do |country|
      OntologySyncSupport.upsert_relationship(
        source_node: entity,
        target_node: country,
        relation_type: relation_type,
        confidence: confidence,
        derived_by: DERIVED_BY,
        explanation: "#{entity.canonical_name} is #{relation_type.tr('_', ' ')} #{country.canonical_name}.",
        metadata: {
          "asset_type" => entity.entity_type,
          "country_canonical_key" => country.canonical_key,
          "country_code" => country.country_code,
          "country_code_alpha3" => country.metadata["country_code_alpha3"],
          "synced_at" => now.iso8601,
        }.compact
      )
      true
    end
  end

  def delete_stale_country_links(entity, relation_type:, keep_country_ids:)
    stale_ids = OntologyRelationship
      .where(source_node: entity, relation_type: relation_type, derived_by: DERIVED_BY, target_node_type: "OntologyEntity")
      .where.not(target_node_id: keep_country_ids)
      .pluck(:id)
    return if stale_ids.empty?

    OntologyRelationshipEvidence.where(ontology_relationship_id: stale_ids).delete_all
    OntologyRelationship.where(id: stale_ids).delete_all
  end

  def resolve_countries(country_codes:, country_names:)
    countries = Array(country_codes).filter_map { |code| identity_resolver.country_for_code(code) }
    countries += Array(country_names).filter_map { |name| identity_resolver.country_for_name(name) }
    countries.uniq(&:id)
  end

  def identity_resolver
    @identity_resolver ||= OntologyV2IdentityService.new(now: now)
  end

  def country_relationship_scope
    OntologyRelationship.where(
      source_node_type: "OntologyEntity",
      target_node_type: "OntologyEntity",
      relation_type: [LOCATED_IN_COUNTRY, LANDS_IN_COUNTRY],
      derived_by: DERIVED_BY
    )
  end

  def asset_scope
    OntologyEntity.where(entity_type: ASSET_ENTITY_TYPES.values)
  end

  def batch_scope_for(target)
    case target
    when "airports"
      Airport.all
    when "military_bases"
      MilitaryBase.all
    when "power_plants"
      PowerPlant.all
    when "ports"
      port_scope
    when "submarine_cables"
      SubmarineCable.all
    end
  end

  def sync_record_for_target(target, record)
    case target
    when "airports"
      sync_airport(record)
    when "military_bases"
      sync_military_base(record)
    when "power_plants"
      sync_power_plant(record)
    when "ports"
      sync_port(record)
    when "submarine_cables"
      sync_submarine_cable(record)
    end
  end

  def port_scope
    TradeLocation.active.where(location_kind: "port")
  end

  def cable_country_refs(cable)
    refs = Array(cable.landing_points).each_with_object({ codes: [], names: [] }) do |point, memo|
      memo[:codes] << (point["country_code"] || point[:country_code])
      memo[:codes] << (point["country_code_alpha3"] || point[:country_code_alpha3])
      memo[:names] << (point["country_name"] || point[:country_name] || point["country"] || point[:country])
    end.transform_values { |values| values.compact_blank.map { |value| value.to_s.strip }.uniq }
    return refs.merge(confidence: 0.82, metadata: { "country_inference" => "landing_points" }) if refs.values.any?(&:any?)

    inferred = infer_cable_country_refs(cable)
    {
      codes: inferred.map { |payload| payload.fetch(:country_code) }.compact_blank.uniq,
      names: inferred.map { |payload| payload.fetch(:country_name) }.compact_blank.uniq,
      confidence: INFERRED_CABLE_COUNTRY_CONFIDENCE,
      metadata: inferred_cable_country_metadata(inferred),
    }
  end

  def military_base_country_refs(base)
    direct_codes = [base.country].compact_blank.map { |value| value.to_s.strip }
    direct_names = [base.country].compact_blank.map { |value| value.to_s.strip }
    return {
      codes: direct_codes,
      names: direct_names,
      confidence: 0.88,
      metadata: { "country_inference" => "source_country_field" },
    } if direct_codes.any? || direct_names.any?

    inferred = nearest_country_payload_from_grid(
      grid: airport_country_grid,
      lat: base.latitude,
      lng: base.longitude,
      radius_km: BASE_COUNTRY_INFERENCE_RADIUS_KM
    )
    return { codes: [], names: [], confidence: 0.0, metadata: {} } if inferred.blank?

    {
      codes: [inferred.fetch(:country_code)],
      names: [inferred[:country_name]],
      confidence: INFERRED_COUNTRY_CONFIDENCE,
      metadata: {
        "country_inference" => "nearest_airport",
        "inferred_country_code" => inferred.fetch(:country_code),
        "country_inference_distance_km" => inferred.fetch(:distance_km).round(1),
        "country_inference_reference" => inferred.fetch(:name),
      }.compact,
    }
  end

  def infer_cable_country_refs(cable)
    cable_endpoint_coordinates(cable.coordinates).filter_map do |lat, lng|
      nearest_country_payload_from_grid(grid: port_country_grid, lat: lat, lng: lng, radius_km: CABLE_COUNTRY_INFERENCE_RADIUS_KM)&.merge(inference_source: "nearest_port") ||
        nearest_country_payload_from_grid(grid: airport_country_grid, lat: lat, lng: lng, radius_km: CABLE_COUNTRY_INFERENCE_RADIUS_KM)&.merge(inference_source: "nearest_airport")
    end.uniq { |payload| payload.fetch(:country_code) }
  end

  def inferred_cable_country_metadata(inferred)
    return {} if inferred.empty?

    {
      "country_inference" => "coordinate_endpoint_nearest_port_or_airport",
      "inferred_country_codes" => inferred.map { |payload| payload.fetch(:country_code) }.compact_blank.uniq,
      "country_inference_references" => inferred.map do |payload|
        {
          "country_code" => payload.fetch(:country_code),
          "reference" => payload.fetch(:name),
          "source" => payload.fetch(:inference_source),
          "distance_km" => payload.fetch(:distance_km).round(1),
        }.compact
      end,
    }
  end

  def cable_endpoint_coordinates(coordinates)
    Array(coordinates).flat_map do |segment|
      pairs = coordinate_pairs(segment)
      [pairs.first, pairs.last]
    end.compact.uniq.filter_map do |pair|
      lng, lat = pair
      next unless valid_coordinate?(lat, lng)

      [lat.to_f, lng.to_f]
    end
  end

  def coordinate_pairs(value)
    return [value] if coordinate_pair?(value)
    return [] unless value.is_a?(Array)

    value.flat_map { |item| coordinate_pairs(item) }
  end

  def coordinate_pair?(value)
    value.is_a?(Array) &&
      value.size >= 2 &&
      value.first.is_a?(Numeric) &&
      value.second.is_a?(Numeric) &&
      valid_coordinate?(value.second, value.first)
  end

  def valid_coordinate?(lat, lng)
    lat.to_f.between?(-90.0, 90.0) && lng.to_f.between?(-180.0, 180.0)
  end

  def nearest_country_payload_from_grid(grid:, lat:, lng:, radius_km:)
    return if lat.blank? || lng.blank?

    lat = lat.to_f
    lng = lng.to_f
    lat_delta = radius_km.to_f / 111.0
    lng_delta = radius_km.to_f / [111.0 * Math.cos(lat * Math::PI / 180.0).abs, 1.0].max
    lat_cells = ((lat - lat_delta).floor..(lat + lat_delta).floor)
    lng_cells = ((lng - lng_delta).floor..(lng + lng_delta).floor)

    lat_cells.flat_map do |lat_cell|
      lng_cells.flat_map { |lng_cell| grid.fetch([lat_cell, lng_cell], []) }
    end.filter_map do |payload|
      next if (payload.fetch(:latitude) - lat).abs > lat_delta || (payload.fetch(:longitude) - lng).abs > lng_delta

      distance = haversine_km(lat, lng, payload.fetch(:latitude), payload.fetch(:longitude))
      next if distance > radius_km

      payload.merge(distance_km: distance)
    end.min_by { |payload| payload.fetch(:distance_km) }
  end

  def airport_country_grid
    @airport_country_grid ||= group_coordinate_payloads_by_degree_cell(
      Airport.where.not(country_code: nil).filter_map do |airport|
        next if airport.country_code.blank?

        {
          latitude: airport.latitude.to_f,
          longitude: airport.longitude.to_f,
          country_code: airport.country_code.to_s.upcase,
          country_name: nil,
          name: airport.name,
        }
      end
    )
  end

  def port_country_grid
    @port_country_grid ||= group_coordinate_payloads_by_degree_cell(
      port_scope.filter_map do |port|
        code = port.country_code.presence || port.country_code_alpha3.presence
        next if code.blank? || port.latitude.blank? || port.longitude.blank?

        {
          latitude: port.latitude.to_f,
          longitude: port.longitude.to_f,
          country_code: code.to_s.upcase,
          country_name: port.country_name,
          name: port.name,
        }
      end
    )
  end

  def group_coordinate_payloads_by_degree_cell(payloads)
    payloads.group_by { |payload| [payload.fetch(:latitude).floor, payload.fetch(:longitude).floor] }
  end

  def iso_like_code(value)
    code = value.to_s.strip
    return code.upcase if code.match?(/\A[A-Za-z]{2,3}\z/)
  end

  def haversine_km(lat1, lng1, lat2, lng2)
    radians_per_degree = Math::PI / 180.0
    dlat = (lat2 - lat1) * radians_per_degree
    dlng = (lng2 - lng1) * radians_per_degree
    a = Math.sin(dlat / 2)**2 +
      Math.cos(lat1 * radians_per_degree) *
      Math.cos(lat2 * radians_per_degree) *
      Math.sin(dlng / 2)**2
    6371.0 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
  end
end
