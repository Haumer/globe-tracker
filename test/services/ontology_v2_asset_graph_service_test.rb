require "test_helper"

class OntologyV2AssetGraphServiceTest < ActiveSupport::TestCase
  test "links ports and cables to canonical country entities" do
    country = create_country
    port = TradeLocation.create!(
      locode: "KWKWI",
      country_code: "KW",
      country_code_alpha3: "KWT",
      country_name: "Kuwait",
      name: "Shuwaikh Port",
      normalized_name: "shuwaikh port",
      location_kind: "port",
      function_codes: "123",
      latitude: 29.35,
      longitude: 47.93,
      status: "active",
      source: "test"
    )
    cable = SubmarineCable.create!(
      cable_id: "gulf-link",
      name: "Gulf Link",
      landing_points: [
        { "country_code" => "KW", "country_name" => "Kuwait" },
        { "country_code" => "BH", "country_name" => "Bahrain" },
      ]
    )

    result = OntologyV2AssetGraphService.sync(now: Time.utc(2026, 4, 11, 12, 0, 0))

    assert_operator result.fetch(:assets), :>=, 2
    assert_operator result.fetch(:country_relationships), :>=, 2

    port_entity = OntologyEntity.find_by!(canonical_key: "port:kwkwi")
    cable_entity = OntologyEntity.find_by!(canonical_key: "submarine-cable:gulf-link")

    assert_equal port, port_entity.ontology_entity_links.find_by!(role: "port").linkable
    assert OntologyRelationship.exists?(
      source_node: port_entity,
      target_node: country,
      relation_type: OntologyV2AssetGraphService::LOCATED_IN_COUNTRY,
      derived_by: OntologyV2AssetGraphService::DERIVED_BY
    )
    assert OntologyRelationship.exists?(
      source_node: cable_entity,
      target_node: country,
      relation_type: OntologyV2AssetGraphService::LANDS_IN_COUNTRY,
      derived_by: OntologyV2AssetGraphService::DERIVED_BY
    )

    assert_not_includes result.dig(:health, :unlocated_assets).map { |row| row.fetch(:canonical_key) }, "submarine-cable:gulf-link"
  end

  test "removes stale country links when asset country changes" do
    kuwait = create_country
    bahrain = OntologyEntity.create!(
      canonical_key: "country:bhr",
      entity_type: "country",
      canonical_name: "Bahrain",
      country_code: "BH",
      metadata: { "country_code_alpha3" => "BHR" }
    )
    port = TradeLocation.create!(
      locode: "KWKWI",
      country_code: "KW",
      country_code_alpha3: "KWT",
      country_name: "Kuwait",
      name: "Shuwaikh Port",
      location_kind: "port",
      latitude: 29.35,
      longitude: 47.93,
      status: "active",
      source: "test"
    )

    OntologyV2AssetGraphService.sync
    port.update!(country_code: "BH", country_code_alpha3: "BHR", country_name: "Bahrain")
    OntologyV2AssetGraphService.sync

    port_entity = OntologyEntity.find_by!(canonical_key: "port:kwkwi")
    assert_not OntologyRelationship.exists?(source_node: port_entity, target_node: kuwait, relation_type: OntologyV2AssetGraphService::LOCATED_IN_COUNTRY)
    assert OntologyRelationship.exists?(source_node: port_entity, target_node: bahrain, relation_type: OntologyV2AssetGraphService::LOCATED_IN_COUNTRY)
  end

  test "infers military base country from nearby airport when source country is blank" do
    country = create_country
    Airport.create!(
      icao_code: "OKBK",
      name: "Kuwait International Airport",
      airport_type: "large_airport",
      latitude: 29.2266,
      longitude: 47.9689,
      country_code: "KW"
    )
    base = MilitaryBase.create!(
      external_id: "osm-base-kuwait",
      name: "Kuwait Test Base",
      base_type: "airfield",
      latitude: 29.25,
      longitude: 47.95,
      source: "test"
    )

    result = OntologyV2AssetGraphService.sync_batch(target: "military_bases", batch_size: 10)

    entity = OntologyEntity.find_by!(canonical_key: "military-base:osm-base-kuwait")
    relationship = OntologyRelationship.find_by!(
      source_node: entity,
      target_node: country,
      relation_type: OntologyV2AssetGraphService::LOCATED_IN_COUNTRY,
      derived_by: OntologyV2AssetGraphService::DERIVED_BY
    )

    assert_equal 1, result.fetch(:records_fetched)
    assert_equal base, entity.ontology_entity_links.find_by!(role: "military_base").linkable
    assert_equal "nearest_airport", entity.metadata["country_inference"]
    assert_equal "KW", entity.metadata["inferred_country_code"]
    assert_equal OntologyV2AssetGraphService::INFERRED_COUNTRY_CONFIDENCE, relationship.confidence
  end

  test "infers cable landing countries from coordinate endpoints near ports" do
    country = create_country
    TradeLocation.create!(
      locode: "KWKWI",
      country_code: "KW",
      country_code_alpha3: "KWT",
      country_name: "Kuwait",
      name: "Shuwaikh Port",
      normalized_name: "shuwaikh port",
      location_kind: "port",
      latitude: 29.35,
      longitude: 47.93,
      status: "active",
      source: "test"
    )
    cable = SubmarineCable.create!(
      cable_id: "coordinate-gulf-link",
      name: "Coordinate Gulf Link",
      coordinates: [
        [
          [47.931, 29.351],
          [48.25, 29.10],
        ],
      ]
    )

    OntologyV2AssetGraphService.sync_batch(target: "submarine_cables", batch_size: 10)

    entity = OntologyEntity.find_by!(canonical_key: "submarine-cable:coordinate-gulf-link")
    relationship = OntologyRelationship.find_by!(
      source_node: entity,
      target_node: country,
      relation_type: OntologyV2AssetGraphService::LANDS_IN_COUNTRY,
      derived_by: OntologyV2AssetGraphService::DERIVED_BY
    )

    assert_equal cable, entity.ontology_entity_links.find_by!(role: "submarine_cable").linkable
    assert_equal "coordinate_endpoint_nearest_port_or_airport", entity.metadata["country_inference"]
    assert_includes entity.metadata["inferred_country_codes"], "KW"
    assert_equal OntologyV2AssetGraphService::INFERRED_CABLE_COUNTRY_CONFIDENCE, relationship.confidence
  end

  private

  def create_country
    OntologyEntity.create!(
      canonical_key: "country:kwt",
      entity_type: "country",
      canonical_name: "Kuwait",
      country_code: "KW",
      metadata: { "country_code_alpha3" => "KWT" }
    )
  end
end
