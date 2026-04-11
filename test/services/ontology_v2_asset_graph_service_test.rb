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
