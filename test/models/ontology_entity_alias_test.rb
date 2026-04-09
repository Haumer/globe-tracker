require "test_helper"

class OntologyEntityAliasTest < ActiveSupport::TestCase
  setup do
    @entity = OntologyEntity.create!(
      canonical_key: "entity-alias-test", entity_type: "state", canonical_name: "Russia"
    )
    @alias_record = OntologyEntityAlias.create!(
      ontology_entity: @entity, name: "Russian Federation", alias_type: "official"
    )
  end

  test "valid creation" do
    assert @alias_record.persisted?
  end

  test "name is required" do
    r = OntologyEntityAlias.new(ontology_entity: @entity, alias_type: "common")
    assert_not r.valid?
    assert_includes r.errors[:name], "can't be blank"
  end

  test "alias_type is required" do
    r = OntologyEntityAlias.new(ontology_entity: @entity, name: "Test")
    r.alias_type = nil
    assert_not r.valid?
    assert_includes r.errors[:alias_type], "can't be blank"
  end

  test "belongs_to ontology_entity" do
    assert_equal @entity, @alias_record.ontology_entity
  end
end
