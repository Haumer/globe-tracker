require "test_helper"

class OntologyEntityTest < ActiveSupport::TestCase
  setup do
    @entity = OntologyEntity.create!(
      canonical_key: "entity-russia",
      entity_type: "state",
      canonical_name: "Russia"
    )
  end

  test "valid creation" do
    assert @entity.persisted?
  end

  test "canonical_key is required" do
    r = OntologyEntity.new(entity_type: "state", canonical_name: "Test")
    assert_not r.valid?
    assert_includes r.errors[:canonical_key], "can't be blank"
  end

  test "entity_type is required" do
    r = OntologyEntity.new(canonical_key: "test", canonical_name: "Test")
    assert_not r.valid?
    assert_includes r.errors[:entity_type], "can't be blank"
  end

  test "canonical_name is required" do
    r = OntologyEntity.new(canonical_key: "test", entity_type: "state")
    assert_not r.valid?
    assert_includes r.errors[:canonical_name], "can't be blank"
  end

  test "parent_entity is optional" do
    assert_nil @entity.parent_entity
  end

  test "child_entities association" do
    child = OntologyEntity.create!(
      canonical_key: "entity-moscow", entity_type: "city",
      canonical_name: "Moscow", parent_entity: @entity
    )
    assert_includes @entity.child_entities, child
  end

  test "has_many ontology_entity_aliases" do
    assert_respond_to @entity, :ontology_entity_aliases
  end

  test "has_many ontology_entity_links" do
    assert_respond_to @entity, :ontology_entity_links
  end

  test "has_many ontology_event_entities" do
    assert_respond_to @entity, :ontology_event_entities
  end

  test "has_many ontology_events through event_entities" do
    assert_respond_to @entity, :ontology_events
  end

  test "has_many outgoing_ontology_relationships" do
    assert_respond_to @entity, :outgoing_ontology_relationships
  end

  test "has_many incoming_ontology_relationships" do
    assert_respond_to @entity, :incoming_ontology_relationships
  end
end
