require "test_helper"

class OntologyV2GraphQueryServiceTest < ActiveSupport::TestCase
  test "groups infrastructure event and geography relationships for a node" do
    country = OntologyEntity.create!(
      canonical_key: "country:kwt",
      entity_type: "country",
      canonical_name: "Kuwait",
      country_code: "KW",
      metadata: { "country_code_alpha3" => "KWT" }
    )
    port = OntologyEntity.create!(
      canonical_key: "port:kwkwi",
      entity_type: "port",
      canonical_name: "Shuwaikh Port"
    )
    event = OntologyEvent.create!(
      canonical_key: "event:kuwait-port-strike",
      event_family: "conflict",
      event_type: "missile_attack",
      status: "active",
      verification_status: "multi_source",
      geo_precision: "point",
      metadata: { "canonical_title" => "Strike near Shuwaikh Port" }
    )

    OntologyRelationship.create!(
      source_node: event,
      target_node: port,
      relation_type: "impacted_infrastructure",
      confidence: 0.84,
      derived_by: OntologyV2InfrastructureImpactService::DERIVED_BY
    )
    OntologyRelationship.create!(
      source_node: event,
      target_node: port,
      relation_type: "targeted_entity",
      confidence: 0.78,
      derived_by: OntologyV2EventGraphService::DERIVED_BY
    )
    OntologyRelationship.create!(
      source_node: port,
      target_node: country,
      relation_type: "located_in_country",
      confidence: 0.88,
      derived_by: OntologyV2AssetGraphService::DERIVED_BY
    )

    graph = OntologyV2GraphQueryService.for_node(kind: "entity", id: "port:kwkwi")
    groups = graph.fetch(:relationship_groups).map { |payload| payload.fetch(:group) }

    assert_equal "Shuwaikh Port", graph.dig(:node, :name)
    assert_includes groups, :infrastructure
    assert_includes groups, :events
    assert_includes groups, :geography
  end
end
