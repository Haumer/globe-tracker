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

  class << self
    def sync(now: Time.current)
      new(now: now).sync
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
    Airport.find_each.sum do |airport|
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
  end

  def sync_military_bases
    MilitaryBase.find_each.sum do |base|
      entity = upsert_asset_entity(
        canonical_key: "military-base:#{base.external_id}",
        entity_type: ASSET_ENTITY_TYPES.fetch(:military_base),
        canonical_name: base.name.presence || base.external_id,
        country_code: iso_like_code(base.country),
        metadata: {
          "base_type" => base.base_type,
          "operator" => base.operator,
          "country" => base.country,
          "latitude" => base.latitude,
          "longitude" => base.longitude,
          "source" => base.source,
        }.compact,
        linkable: base,
        link_role: "military_base",
        aliases: { "official" => base.name, "external_id" => base.external_id }
      )
      link_asset_country(entity, country_codes: [base.country], country_names: [base.country])
    end
  end

  def sync_power_plants
    PowerPlant.find_each.sum do |plant|
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
  end

  def sync_ports
    TradeLocation.active.where(location_kind: "port").find_each.sum do |port|
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
  end

  def sync_submarine_cables
    SubmarineCable.find_each.sum do |cable|
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
        }.compact,
        linkable: cable,
        link_role: "submarine_cable",
        aliases: { "official" => cable.name, "external_id" => cable.cable_id }
      )
      link_asset_country(
        entity,
        country_codes: country_refs.fetch(:codes),
        country_names: country_refs.fetch(:names),
        relation_type: LANDS_IN_COUNTRY,
        confidence: 0.82
      )
    end
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

  def cable_country_refs(cable)
    Array(cable.landing_points).each_with_object({ codes: [], names: [] }) do |point, memo|
      memo[:codes] << (point["country_code"] || point[:country_code])
      memo[:codes] << (point["country_code_alpha3"] || point[:country_code_alpha3])
      memo[:names] << (point["country_name"] || point[:country_name] || point["country"] || point[:country])
    end.transform_values { |values| values.compact_blank.map { |value| value.to_s.strip }.uniq }
  end

  def iso_like_code(value)
    code = value.to_s.strip
    return code.upcase if code.match?(/\A[A-Za-z]{2,3}\z/)
  end
end
