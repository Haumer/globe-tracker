require "test_helper"

class Api::SituationLayersControllerTest < ActionDispatch::IntegrationTest
  test "unknown situation is a 404" do
    get "/api/situations/999999/layers"
    assert_response :not_found
  end

  test "returns the plan for a real situation" do
    cluster = NewsStoryCluster.create!(
      cluster_key: "c1", canonical_title: "Strike", event_family: "conflict", event_type: "airstrike",
      verification_status: "single_source", geo_precision: "unknown", cluster_confidence: 0.6,
      source_reliability: 0.6, geo_confidence: 0.0, first_seen_at: 3.days.ago, last_seen_at: 1.day.ago,
      article_count: 4
    )
    event = OntologyEvent.create!(
      canonical_key: "news-story-cluster:c1", primary_story_cluster: cluster,
      event_family: "conflict", event_type: "airstrike", last_seen_at: 1.day.ago,
      latitude: 50.4, longitude: 30.5
    )
    entity = OntologyEntity.create!(
      canonical_key: "situation:test:1", entity_type: "situation", canonical_name: "Kyiv situation",
      metadata: { "grouped_by" => "entity" }
    )
    OntologyEventEntity.create!(ontology_event: event, ontology_entity: entity, role: "in_situation")

    get "/api/situations/#{entity.id}/layers"

    assert_response :success
    plan = JSON.parse(response.body)
    assert_equal entity.id, plan["situation_id"]
    assert_equal SituationLayerPlanService::CATALOG.size, plan["layers"].size
    assert plan["layers"].all? { |l| l.key?("status") && l.key?("sources") }
  end
end
