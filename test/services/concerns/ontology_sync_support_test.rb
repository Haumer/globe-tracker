require "test_helper"

class OntologySyncSupportTest < ActiveSupport::TestCase
  # Re-deriving something that has not changed used to rewrite it anyway,
  # because each sync stamped a synced_at nobody reads. That made every row
  # dirty on every pass and moved updated_at, which is what incremental passes
  # filter on.
  test "re-upserting an unchanged record does not write" do
    entity = OntologySyncSupport.upsert_entity(
      canonical_key: "test:unchanged",
      entity_type: "asset",
      canonical_name: "Unchanged Asset",
      metadata: { "synced_at" => 1.hour.ago.iso8601, "kind" => "port" }
    )
    stamp = entity.reload.updated_at

    travel 5.minutes do
      OntologySyncSupport.upsert_entity(
        canonical_key: "test:unchanged",
        entity_type: "asset",
        canonical_name: "Unchanged Asset",
        metadata: { "synced_at" => Time.current.iso8601, "kind" => "port" }
      )
    end

    assert_equal stamp, entity.reload.updated_at, "a no-op re-sync must not touch the row"
  end

  test "a real change is still written" do
    OntologySyncSupport.upsert_entity(
      canonical_key: "test:changed",
      entity_type: "asset",
      canonical_name: "Original Name",
      metadata: { "synced_at" => 1.hour.ago.iso8601 }
    )

    OntologySyncSupport.upsert_entity(
      canonical_key: "test:changed",
      entity_type: "asset",
      canonical_name: "Renamed Asset",
      metadata: { "synced_at" => Time.current.iso8601 }
    )

    entity = OntologyEntity.find_by!(canonical_key: "test:changed")
    assert_equal "Renamed Asset", entity.canonical_name
  end

  test "a metadata change outside the touch keys is still written" do
    OntologySyncSupport.upsert_entity(
      canonical_key: "test:meta",
      entity_type: "asset",
      canonical_name: "Meta Asset",
      metadata: { "synced_at" => 1.hour.ago.iso8601, "capacity" => "10" }
    )

    OntologySyncSupport.upsert_entity(
      canonical_key: "test:meta",
      entity_type: "asset",
      canonical_name: "Meta Asset",
      metadata: { "synced_at" => Time.current.iso8601, "capacity" => "20" }
    )

    entity = OntologyEntity.find_by!(canonical_key: "test:meta")
    assert_equal "20", entity.metadata["capacity"]
  end

  test "upsert_link retries after a duplicate insert race" do
    entity = OntologyEntity.create!(
      canonical_key: "test:ship",
      entity_type: "asset",
      canonical_name: "Test Ship"
    )
    ship = Ship.create!(mmsi: "123456789", name: "Race Vessel")

    original_save = OntologyEntityLink.instance_method(:save!)
    save_calls = 0

    OntologyEntityLink.class_eval do
      define_method(:save!) do |*args, **kwargs|
        save_calls += 1

        result = if kwargs.empty?
          original_save.bind_call(self, *args)
        else
          original_save.bind_call(self, *args, **kwargs)
        end

        raise ActiveRecord::RecordNotUnique, "simulated duplicate insert" if save_calls == 1

        result
      end
    end

    link = OntologySyncSupport.upsert_link(
      entity,
      ship,
      role: "tracked_ship",
      method: "test",
      confidence: 0.9,
      metadata: { "source" => "test" }
    )

    assert_equal 1, OntologyEntityLink.where(ontology_entity: entity, linkable: ship, role: "tracked_ship").count
    assert_equal ship, link.linkable
    assert_equal "test", link.method
    assert_equal 0.9, link.confidence
    assert_equal({ "source" => "test" }, link.metadata)
  ensure
    OntologyEntityLink.class_eval do
      define_method(:save!, original_save)
    end
  end
end
