require "test_helper"

class ObjectsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "object view renders durable node context" do
    theater = OntologyEntity.create!(
      canonical_key: "theater:test-theater",
      entity_type: "theater",
      canonical_name: "Test Theater",
      metadata: { "cluster_count" => 4, "total_sources" => 11, "situation_names" => ["Hormuz", "Gulf States"] }
    )
    chokepoint = OntologyEntity.create!(
      canonical_key: "corridor:chokepoint:hormuz",
      entity_type: "corridor",
      canonical_name: "Strait of Hormuz",
      metadata: { "description" => "Strategic energy corridor", "latitude" => 26.56, "longitude" => 56.27 }
    )
    cluster = create_story_cluster("cluster:hormuz", "Shipping pressure builds around Hormuz")

    relationship = OntologyRelationship.create!(
      source_node: theater,
      target_node: chokepoint,
      relation_type: "theater_pressure",
      confidence: 0.93,
      fresh_until: 2.hours.from_now,
      derived_by: "test",
      explanation: "Test Theater is exerting pressure on Strait of Hormuz"
    )
    OntologyRelationshipEvidence.create!(
      ontology_relationship: relationship,
      evidence: cluster,
      evidence_role: "local_story",
      confidence: 0.84
    )

    get object_view_path(kind: "chokepoint", id: "Strait of Hormuz")

    assert_response :success
    assert_includes response.body, "Object View"
    assert_includes response.body, "Strait of Hormuz"
    assert_includes response.body, "Open On Globe"
    assert_includes response.body, "Test Theater"
    assert_includes response.body, "/api/node_context?"
    assert_includes response.body, "kind=chokepoint"
    assert_includes response.body, "id=Strait+of+Hormuz"
  end

  test "object view exposes case intake for signed-in users" do
    user = User.create!(email: "object-case@example.com", password: "password123")
    sign_in user

    OntologyEntity.create!(
      canonical_key: "theater:test-theater",
      entity_type: "theater",
      canonical_name: "Test Theater",
      metadata: { "description" => "Monitor the theater", "latitude" => 24.0, "longitude" => 54.0 }
    )
    user.investigation_cases.create!(title: "Existing theater case")

    get object_view_path(kind: "theater", id: "Test Theater")

    assert_response :success
    assert_includes response.body, "Create Case From Object"
    assert_includes response.body, "Add To Existing Case"
    assert_includes response.body, "Existing theater case"
  end

  test "object view returns not found for missing durable node" do
    get object_view_path(kind: "entity", id: "missing-node")

    assert_response :not_found
    assert_includes response.body, "Durable context unavailable"
    assert_includes response.body, "entity context not found"
  end

  private

  def create_story_cluster(key, title)
    NewsStoryCluster.create!(
      cluster_key: key,
      canonical_title: title,
      content_scope: "core",
      event_family: "conflict",
      event_type: "military_activity",
      location_name: "Hormuz",
      latitude: 26.7,
      longitude: 56.4,
      geo_precision: "point",
      first_seen_at: 1.hour.ago,
      last_seen_at: 20.minutes.ago,
      article_count: 3,
      source_count: 3,
      cluster_confidence: 0.84,
      verification_status: "multi_source",
      source_reliability: 0.78,
      geo_confidence: 0.82
    )
  end
end
