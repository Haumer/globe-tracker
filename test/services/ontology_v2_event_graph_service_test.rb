require "test_helper"

class OntologyV2EventGraphServiceTest < ActiveSupport::TestCase
  test "materializes typed event graph relationships with mirrored evidence" do
    place = create_entity("place:kuwait", "place", "Kuwait")
    actor = create_entity("actor:state:ir", "actor", "Iran")
    target = create_entity("country:kwt", "country", "Kuwait", country_code: "KW", metadata: { "country_code_alpha3" => "KWT" })
    evidence = create_story_cluster("cluster:kuwait-strike")
    event = create_event("event:kuwait-strike", place_entity: place)

    OntologyEventEntity.create!(ontology_event: event, ontology_entity: actor, role: "initiator", confidence: 0.84)
    OntologyEventEntity.create!(ontology_event: event, ontology_entity: target, role: "target", confidence: 0.76)
    OntologyEvidenceLink.create!(ontology_event: event, evidence: evidence, evidence_role: "primary_cluster", confidence: 0.91)

    result = OntologyV2EventGraphService.sync(now: Time.utc(2026, 4, 11, 12, 0, 0))

    assert_equal 1, result.fetch(:events)
    assert_equal 1, result.fetch(:place_relationships)
    assert_equal 2, result.fetch(:entity_relationships)
    assert_equal 3, result.fetch(:relationship_evidences)

    occurred_at = OntologyRelationship.find_by!(
      source_node: event,
      target_node: place,
      relation_type: OntologyV2EventGraphService::OCCURRED_AT
    )
    initiated = OntologyRelationship.find_by!(
      source_node: actor,
      target_node: event,
      relation_type: "initiated_event"
    )
    targeted = OntologyRelationship.find_by!(
      source_node: event,
      target_node: target,
      relation_type: "targeted_entity"
    )

    [occurred_at, initiated, targeted].each do |relationship|
      assert_equal OntologyV2EventGraphService::DERIVED_BY, relationship.derived_by
      assert relationship.ontology_relationship_evidences.exists?(
        evidence: evidence,
        evidence_role: "event_primary_cluster"
      )
    end
  end

  test "health report flags events that cannot support serious analysis" do
    incomplete = OntologyEvent.create!(
      canonical_key: "event:weak",
      event_family: "conflict",
      event_type: "missile_attack",
      status: "active",
      verification_status: "single_source",
      geo_precision: "unknown"
    )
    actor = create_entity("actor:state:ir", "actor", "Iran")
    evidence = create_story_cluster("cluster:complete")
    complete = create_event("event:complete", place_entity: create_entity("place:tehran", "place", "Tehran"))
    OntologyEventEntity.create!(ontology_event: complete, ontology_entity: actor, role: "initiator")
    OntologyEvidenceLink.create!(ontology_event: complete, evidence: evidence, evidence_role: "primary_cluster")

    report = OntologyV2EventGraphService.health_report

    assert_includes report.fetch(:events_missing_evidence).map { |row| row.fetch(:canonical_key) }, incomplete.canonical_key
    assert_includes report.fetch(:events_missing_actor).map { |row| row.fetch(:canonical_key) }, incomplete.canonical_key
    assert_includes report.fetch(:events_missing_location_or_target).map { |row| row.fetch(:canonical_key) }, incomplete.canonical_key
    assert_includes report.fetch(:events_missing_time).map { |row| row.fetch(:canonical_key) }, incomplete.canonical_key
    assert_not_includes report.fetch(:events_missing_evidence).map { |row| row.fetch(:canonical_key) }, complete.canonical_key
  end

  test "removes stale event graph relationships when event membership changes" do
    actor = create_entity("actor:state:ir", "actor", "Iran")
    target = create_entity("country:kwt", "country", "Kuwait")
    event = create_event("event:changing")
    membership = OntologyEventEntity.create!(ontology_event: event, ontology_entity: actor, role: "initiator")

    OntologyV2EventGraphService.sync

    assert OntologyRelationship.exists?(source_node: actor, target_node: event, relation_type: "initiated_event")

    membership.destroy!
    OntologyEventEntity.create!(ontology_event: event, ontology_entity: target, role: "target")

    OntologyV2EventGraphService.sync

    assert_not OntologyRelationship.exists?(source_node: actor, target_node: event, relation_type: "initiated_event")
    assert OntologyRelationship.exists?(source_node: event, target_node: target, relation_type: "targeted_entity")
  end

  test "sync batch processes only the requested cursor window" do
    first = create_event("event:first")
    second = create_event("event:second")
    actor = create_entity("actor:state:ir", "actor", "Iran")
    OntologyEventEntity.create!(ontology_event: first, ontology_entity: actor, role: "initiator")
    OntologyEventEntity.create!(ontology_event: second, ontology_entity: actor, role: "initiator")

    result = OntologyV2EventGraphService.sync_batch(batch_size: 1)

    assert_equal 1, result.fetch(:records_fetched)
    assert_equal first.id, result.fetch(:next_cursor)
    assert_not result.fetch(:complete)
    assert OntologyRelationship.exists?(source_node: actor, target_node: first, relation_type: "initiated_event")
    assert_not OntologyRelationship.exists?(source_node: actor, target_node: second, relation_type: "initiated_event")
  end

  private

  def create_event(canonical_key, place_entity: nil)
    OntologyEvent.create!(
      canonical_key: canonical_key,
      event_family: "conflict",
      event_type: "missile_attack",
      status: "active",
      place_entity: place_entity,
      verification_status: "multi_source",
      geo_precision: place_entity.present? ? "point" : "unknown",
      confidence: 0.82,
      geo_confidence: place_entity.present? ? 0.7 : 0.0,
      first_seen_at: Time.utc(2026, 4, 11, 11, 45, 0),
      last_seen_at: Time.utc(2026, 4, 11, 12, 0, 0),
      metadata: { "canonical_title" => "Iran strikes Kuwait target" }
    )
  end

  def create_entity(canonical_key, entity_type, canonical_name, country_code: nil, metadata: {})
    OntologyEntity.create!(
      canonical_key: canonical_key,
      entity_type: entity_type,
      canonical_name: canonical_name,
      country_code: country_code,
      metadata: metadata
    )
  end

  def create_story_cluster(cluster_key)
    NewsStoryCluster.create!(
      cluster_key: cluster_key,
      canonical_title: "Iran strikes Kuwait target",
      content_scope: "core",
      event_family: "conflict",
      event_type: "missile_attack",
      geo_precision: "point",
      first_seen_at: Time.utc(2026, 4, 11, 11, 45, 0),
      last_seen_at: Time.utc(2026, 4, 11, 12, 0, 0),
      verification_status: "multi_source"
    )
  end
end
