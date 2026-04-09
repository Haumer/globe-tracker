require "test_helper"

class OntologyEventTest < ActiveSupport::TestCase
  setup do
    @event = OntologyEvent.create!(
      canonical_key: "event-strike-001",
      event_family: "conflict",
      event_type: "military_strike",
      status: "active",
      verification_status: "multi_source",
      geo_precision: "city"
    )
  end

  test "valid creation" do
    assert @event.persisted?
  end

  test "canonical_key is required" do
    r = OntologyEvent.new(event_family: "conflict", event_type: "strike", status: "active", verification_status: "unverified", geo_precision: "unknown")
    assert_not r.valid?
    assert_includes r.errors[:canonical_key], "can't be blank"
  end

  test "event_family is required" do
    r = OntologyEvent.new(canonical_key: "x", event_type: "strike", status: "active", verification_status: "unverified", geo_precision: "unknown")
    r.event_family = nil
    assert_not r.valid?
    assert_includes r.errors[:event_family], "can't be blank"
  end

  test "status is required" do
    r = OntologyEvent.new(canonical_key: "x", event_family: "conflict", event_type: "strike", verification_status: "unverified", geo_precision: "unknown")
    r.status = nil
    assert_not r.valid?
    assert_includes r.errors[:status], "can't be blank"
  end

  test "place_entity is optional" do
    assert_nil @event.place_entity
  end

  test "primary_story_cluster is optional" do
    assert_nil @event.primary_story_cluster
  end

  test "has_many ontology_event_entities" do
    assert_respond_to @event, :ontology_event_entities
  end

  test "has_many ontology_entities through event_entities" do
    assert_respond_to @event, :ontology_entities
  end

  test "has_many ontology_evidence_links" do
    assert_respond_to @event, :ontology_evidence_links
  end

  test "has_many outgoing_ontology_relationships" do
    assert_respond_to @event, :outgoing_ontology_relationships
  end

  test "has_many incoming_ontology_relationships" do
    assert_respond_to @event, :incoming_ontology_relationships
  end
end
