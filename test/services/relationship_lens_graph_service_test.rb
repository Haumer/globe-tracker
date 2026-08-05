require "test_helper"

class RelationshipLensGraphServiceTest < ActiveSupport::TestCase
  test "build promotes market metrics into graph nodes" do
    theater = OntologyEntity.create!(
      canonical_key: "theater:lens-test",
      entity_type: "theater",
      canonical_name: "Lens Test Theater"
    )
    corridor = OntologyEntity.create!(
      canonical_key: "corridor:chokepoint:lens_test",
      entity_type: "corridor",
      canonical_name: "Lens Test Strait"
    )
    crude = OntologyEntity.create!(
      canonical_key: "commodity:oil_crude",
      entity_type: "commodity",
      canonical_name: "Crude Oil"
    )
    brent = OntologyEntity.create!(
      canonical_key: "commodity:oil_brent",
      entity_type: "commodity",
      canonical_name: "Brent Crude"
    )
    country = OntologyEntity.create!(
      canonical_key: "country:tst",
      entity_type: "country",
      canonical_name: "Test Importer"
    )
    sector = OntologyEntity.create!(
      canonical_key: "sector:tst:industry",
      entity_type: "sector",
      canonical_name: "Test Importer Industry",
      metadata: { "share_pct" => 22.4 }
    )

    OntologyRelationship.create!(
      source_node: theater,
      target_node: corridor,
      relation_type: "theater_pressure",
      confidence: 0.9,
      derived_by: "test"
    )
    OntologyRelationship.create!(
      source_node: corridor,
      target_node: crude,
      relation_type: "flow_dependency",
      confidence: 0.8,
      derived_by: "test"
    )
    OntologyRelationship.create!(
      source_node: corridor,
      target_node: brent,
      relation_type: "flow_dependency",
      confidence: 0.75,
      derived_by: "test",
      metadata: { "commodity_symbol" => "OIL_BRENT", "latest_change_pct" => 6.4 }
    )
    OntologyRelationship.create!(
      source_node: corridor,
      target_node: country,
      relation_type: "chokepoint_exposure",
      confidence: 0.8,
      derived_by: "test",
      metadata: { "commodities" => ["oil_crude"], "max_exposure_score" => 0.4 }
    )
    OntologyRelationship.create!(
      source_node: crude,
      target_node: country,
      relation_type: "import_dependency",
      confidence: 0.7,
      derived_by: "test",
      metadata: { "dependency_score" => 0.62 }
    )
    OntologyRelationship.create!(
      source_node: crude,
      target_node: sector,
      relation_type: "production_dependency",
      confidence: 0.5,
      derived_by: "test"
    )

    graph = RelationshipLensGraphService.build
    chain = graph.fetch(:chains).find { |candidate| candidate.fetch(:title).include?("Lens Test Theater") }

    assert chain, "expected the test chain to be surfaced"
    assert_includes graph.fetch(:nodes).map { |node| node.fetch(:label) }, "OIL_BRENT"
    assert_includes chain.fetch(:path).map { |node| node.fetch(:role) }, "Market"
    assert graph.fetch(:edges).any? { |edge| edge.fetch(:source_label) == "Crude Oil" && edge.fetch(:target_label) == "OIL_BRENT" }
    assert graph.fetch(:stats).fetch(:chains) >= 1
  end
end
