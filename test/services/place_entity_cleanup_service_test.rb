require "test_helper"

class PlaceEntityCleanupServiceTest < ActiveSupport::TestCase
  def setup
    NewsSource.create!(canonical_key: "publisher:wapo", name: "Washington Post", publisher_domain: "washingtonpost.com")

    @masthead = OntologyEntity.create!(
      canonical_key: "place:washington-post", entity_type: "place", canonical_name: "Washington Post",
      metadata: { "latitude" => 26.567, "longitude" => 56.25 }
    )
    @prefixed = OntologyEntity.create!(
      canonical_key: "place:gn-jerusalem-post", entity_type: "place", canonical_name: "GN: Jerusalem Post"
    )
    @fire = OntologyEntity.create!(
      canonical_key: "place:extreme-fire-fc-2279", entity_type: "place", canonical_name: "Extreme fire fc_2279_-5910"
    )
    @genuine = OntologyEntity.create!(
      canonical_key: "place:chennai:in", entity_type: "place", canonical_name: "Chennai", country_code: "IN",
      metadata: { "latitude" => 13.09, "longitude" => 80.28 }
    )
    @event = OntologyEvent.create!(
      canonical_key: "news-story-cluster:cleanup-test", event_family: "conflict", event_type: "airstrike",
      last_seen_at: 1.day.ago, place_entity: @masthead
    )
  end

  test "dry run reports without deleting" do
    report = PlaceEntityCleanupService.call

    assert_equal 1, report.mastheads, "prefixed masthead needs a source entity to match; only wapo counts here"
    assert_equal 1, report.fires
    assert_equal 1, report.events_detached
    assert_not report.applied
    assert OntologyEntity.exists?(@masthead.id)
    assert OntologyEntity.exists?(@fire.id)
    assert_equal @masthead, @event.reload.place_entity
  end

  test "feed prefixes are stripped before matching a source entity" do
    OntologyEntity.create!(canonical_key: "source:jpost", entity_type: "source", canonical_name: "Jerusalem Post")

    report = PlaceEntityCleanupService.call

    assert_equal 2, report.mastheads
    assert_includes report.samples, "GN: Jerusalem Post"
  end

  test "apply deletes mastheads and fires, detaches events, keeps real places" do
    # A relationship with evidence, the chain that made the naive destroy raise.
    relationship = OntologyRelationship.create!(
      source_node: @event, target_node: @masthead, relation_type: "occurred_at",
      confidence: 0.5, derived_by: "news_ontology_sync_v1"
    )
    OntologyRelationshipEvidence.create!(
      ontology_relationship: relationship, evidence: @event.primary_story_cluster || @masthead,
      evidence_role: "primary", confidence: 0.5
    )

    report = PlaceEntityCleanupService.call(apply: true)

    assert report.applied
    assert_not OntologyEntity.exists?(@masthead.id)
    assert_not OntologyEntity.exists?(@fire.id)
    assert OntologyEntity.exists?(@prefixed.id), "unmatched oddities stay for a human"
    assert OntologyEntity.exists?(@genuine.id)
    assert_nil @event.reload.place_entity
    assert_equal 1, report.events_detached
  end
end
