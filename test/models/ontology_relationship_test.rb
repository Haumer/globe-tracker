require "test_helper"

class OntologyRelationshipTest < ActiveSupport::TestCase
  setup do
    @entity1 = OntologyEntity.create!(
      canonical_key: "rel-entity-1", entity_type: "state", canonical_name: "Russia"
    )
    @entity2 = OntologyEntity.create!(
      canonical_key: "rel-entity-2", entity_type: "state", canonical_name: "Ukraine"
    )
    @rel = OntologyRelationship.create!(
      source_node: @entity1, target_node: @entity2,
      relation_type: "adversary", derived_by: "sync",
      fresh_until: 1.day.from_now
    )
  end

  test "valid creation" do
    assert @rel.persisted?
  end

  test "relation_type is required" do
    r = OntologyRelationship.new(source_node: @entity1, target_node: @entity2, derived_by: "sync")
    r.relation_type = nil
    assert_not r.valid?
    assert_includes r.errors[:relation_type], "can't be blank"
  end

  test "derived_by is required" do
    r = OntologyRelationship.new(source_node: @entity1, target_node: @entity2, relation_type: "ally")
    r.derived_by = nil
    assert_not r.valid?
    assert_includes r.errors[:derived_by], "can't be blank"
  end

  test "belongs_to source_node polymorphic" do
    assert_equal @entity1, @rel.source_node
  end

  test "belongs_to target_node polymorphic" do
    assert_equal @entity2, @rel.target_node
  end

  test "has_many ontology_relationship_evidences" do
    assert_respond_to @rel, :ontology_relationship_evidences
  end

  test "active? returns true when fresh_until is in future" do
    assert @rel.active?
  end

  test "active? returns true when fresh_until is nil" do
    @rel.fresh_until = nil
    assert @rel.active?
  end

  test "active? returns false when expired" do
    @rel.fresh_until = 1.day.ago
    assert_not @rel.active?
  end

  test "active scope returns non-expired relationships" do
    expired = OntologyRelationship.create!(
      source_node: @entity1, target_node: @entity2,
      relation_type: "ally", derived_by: "sync",
      fresh_until: 1.day.ago
    )
    results = OntologyRelationship.active
    assert_includes results, @rel
    assert_not_includes results, expired
  end
end
