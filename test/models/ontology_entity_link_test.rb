require "test_helper"

class OntologyEntityLinkTest < ActiveSupport::TestCase
  setup do
    @entity = OntologyEntity.create!(
      canonical_key: "entity-link-test", entity_type: "org", canonical_name: "NATO"
    )
    @actor = NewsActor.create!(canonical_key: "nato-link", name: "NATO", actor_type: "org")
    @link = OntologyEntityLink.create!(
      ontology_entity: @entity, linkable: @actor, role: "primary", method: "sync"
    )
  end

  test "valid creation" do
    assert @link.persisted?
  end

  test "role is required" do
    r = OntologyEntityLink.new(ontology_entity: @entity, linkable: @actor, method: "sync")
    r.role = nil
    assert_not r.valid?
    assert_includes r.errors[:role], "can't be blank"
  end

  test "method is required" do
    r = OntologyEntityLink.new(ontology_entity: @entity, linkable: @actor, role: "primary")
    r.method = nil
    assert_not r.valid?
    assert_includes r.errors[:method], "can't be blank"
  end

  test "belongs_to ontology_entity" do
    assert_equal @entity, @link.ontology_entity
  end

  test "belongs_to linkable (polymorphic)" do
    assert_equal @actor, @link.linkable
  end
end
