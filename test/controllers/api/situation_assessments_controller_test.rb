require "test_helper"

class Api::SituationAssessmentsControllerTest < ActionDispatch::IntegrationTest
  test "returns assessment for an ontology node" do
    country = OntologyEntity.create!(
      canonical_key: "country:test",
      entity_type: "country",
      canonical_name: "Testland",
      country_code: "TS",
      metadata: { "description" => "Test country" }
    )
    commodity = OntologyEntity.create!(
      canonical_key: "commodity:oil_test",
      entity_type: "commodity",
      canonical_name: "Test Oil"
    )
    dependency = OntologyRelationship.create!(
      source_node: commodity,
      target_node: country,
      relation_type: "import_dependency",
      confidence: 0.74,
      derived_by: "test",
      explanation: "Testland depends on imported Test Oil"
    )
    OntologyRelationshipEvidence.create!(
      ontology_relationship: dependency,
      evidence: CountryCommodityDependency.create!(
        country_code: "TS",
        country_code_alpha3: "TST",
        country_name: "Testland",
        commodity_key: "oil_test",
        commodity_name: "Test Oil",
        supplier_count: 1,
        dependency_score: 0.74,
        metadata: {},
        fetched_at: Time.current
      ),
      evidence_role: "dependency_profile",
      confidence: 0.74
    )

    get "/api/situation_assessment", params: { kind: "entity", id: "country:test" }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "country:test", body.dig("node", "canonical_key")
    assert_equal "supply_chain_exposure", body.fetch("situation_type")
    assert_includes body.fetch("inferred").join(" "), "Testland depends on imported Test Oil"
    assert_equal "import_dependency", body.dig("affected_entities", 0, "relation_type")
  end

  test "returns recent ontology-backed situation assessments" do
    country = OntologyEntity.create!(
      canonical_key: "country:test",
      entity_type: "country",
      canonical_name: "Testland"
    )
    commodity = OntologyEntity.create!(
      canonical_key: "commodity:oil_test",
      entity_type: "commodity",
      canonical_name: "Test Oil"
    )
    relationship = OntologyRelationship.create!(
      source_node: commodity,
      target_node: country,
      relation_type: "import_dependency",
      confidence: 0.74,
      derived_by: "test",
      explanation: "Testland depends on imported Test Oil"
    )
    OntologyRelationshipEvidence.create!(
      ontology_relationship: relationship,
      evidence: NewsStoryCluster.create!(
        cluster_key: "cluster:testland-oil",
        canonical_title: "Testland faces imported oil pressure",
        content_scope: "core",
        event_family: "economy",
        event_type: "commodity_pressure",
        location_name: "Testland",
        latitude: 1.0,
        longitude: 2.0,
        geo_precision: "country",
        first_seen_at: 1.hour.ago,
        last_seen_at: 20.minutes.ago,
        article_count: 3,
        source_count: 3,
        cluster_confidence: 0.82,
        verification_status: "multi_source",
        source_reliability: 0.75,
        geo_confidence: 0.7
      ),
      evidence_role: "supporting_story",
      confidence: 0.82
    )

    get "/api/situation_assessments", params: { limit: 5 }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "Testland", body.dig("situations", 0, "title")
    assert_equal "supply_chain_exposure", body.dig("situations", 0, "situation_type")
  end

  test "returns not found for missing ontology node" do
    get "/api/situation_assessment", params: { kind: "entity", id: "country:missing" }

    assert_response :not_found
  end
end
