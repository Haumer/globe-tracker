require "test_helper"

class OntologySyncSupportTest < ActiveSupport::TestCase
  test "upsert_entity creates then updates the same canonical key" do
    key = "asset:flight:icao24:aaa111"

    created = OntologySyncSupport.upsert_entity(
      canonical_key: key,
      entity_type: "asset",
      canonical_name: "First",
      metadata: { "a" => 1 }
    )
    updated = OntologySyncSupport.upsert_entity(
      canonical_key: key,
      entity_type: "asset",
      canonical_name: "Second",
      metadata: { "b" => 2 }
    )

    assert_equal created.id, updated.id
    assert_equal 1, OntologyEntity.where(canonical_key: key).count
    assert_equal "Second", updated.canonical_name
    assert_equal({ "a" => 1, "b" => 2 }, updated.metadata)
  end

  # Reproduces the production failure: two workers sync the same flight
  # concurrently, both find no row, and the slower one hits the unique index
  # on canonical_key. The upsert must recover instead of raising.
  test "upsert_entity recovers when another process inserts the same key first" do
    key = "asset:flight:icao24:bbb222"
    original = OntologyEntity.method(:find_or_initialize_by)
    calls = 0

    racing_lookup = lambda do |attributes|
      calls += 1
      if calls == 1
        # A competing worker commits the row after our lookup, before our save.
        OntologyEntity.create!(canonical_key: key, entity_type: "asset", canonical_name: "Winner")
        OntologyEntity.new(canonical_key: key)
      else
        original.call(attributes)
      end
    end

    entity = OntologyEntity.stub(:find_or_initialize_by, racing_lookup) do
      OntologySyncSupport.upsert_entity(canonical_key: key, entity_type: "asset", canonical_name: "Loser")
    end

    assert_equal 2, calls, "expected one retry after the unique violation"
    assert_predicate entity, :persisted?
    assert_equal 1, OntologyEntity.where(canonical_key: key).count
    assert_equal "Loser", entity.reload.canonical_name
  end

  test "upsert_alias is idempotent and keeps the original alias type" do
    entity = OntologySyncSupport.upsert_entity(
      canonical_key: "country:test-alias",
      entity_type: "country",
      canonical_name: "Testland"
    )

    first = OntologySyncSupport.upsert_alias(entity, "Testland", alias_type: "official")
    second = OntologySyncSupport.upsert_alias(entity, "Testland", alias_type: "common")

    assert_equal first.id, second.id
    assert_equal 1, OntologyEntityAlias.where(ontology_entity: entity, name: "Testland").count
    assert_equal "official", second.reload.alias_type
  end
end
