require "test_helper"

class OntologySyncSupportTest < ActiveSupport::TestCase
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
