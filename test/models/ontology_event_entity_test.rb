require "test_helper"

class OntologyEventEntityTest < ActiveSupport::TestCase
  setup do
    @entity = OntologyEntity.create!(
      canonical_key: "entity-ee-test", entity_type: "state", canonical_name: "Ukraine"
    )
    @event = OntologyEvent.create!(
      canonical_key: "event-ee-001", event_family: "conflict", event_type: "strike",
      status: "active", verification_status: "unverified", geo_precision: "unknown"
    )
    @event_entity = OntologyEventEntity.create!(
      ontology_event: @event, ontology_entity: @entity, role: "target"
    )
  end

  test "valid creation" do
    assert @event_entity.persisted?
  end

  test "role is required" do
    r = OntologyEventEntity.new(ontology_event: @event, ontology_entity: @entity)
    r.role = nil
    assert_not r.valid?
    assert_includes r.errors[:role], "can't be blank"
  end

  test "belongs_to ontology_event" do
    assert_equal @event, @event_entity.ontology_event
  end

  test "belongs_to ontology_entity" do
    assert_equal @entity, @event_entity.ontology_entity
  end
end
