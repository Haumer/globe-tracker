require "test_helper"

class RegistryEntityResolverTest < ActiveSupport::TestCase
  setup do
    @refinery = OntologyEntity.create!(
      canonical_key: "power-plant:jazan", entity_type: "power_plant", canonical_name: "JAZAN",
      country_code: "SA", metadata: { "latitude" => 16.94, "longitude" => 42.633 }
    )
    @port = OntologyEntity.create!(
      canonical_key: "port:jizan", entity_type: "port", canonical_name: "JIZAN",
      country_code: "SA", metadata: { "latitude" => 16.9, "longitude" => 42.48 }
    )
  end

  def match_for(entity)
    RegistryNameIndex::Match.new(
      surface: entity.canonical_name.downcase, entity_id: entity.id,
      entity_type: entity.entity_type, entity_name: entity.canonical_name, facility_named: false
    )
  end

  def stub(reply)
    ->(_prompt) { reply }
  end

  test "resolves the chosen candidate to a foreign key" do
    candidates = [match_for(@port), match_for(@refinery)]

    result = RegistryEntityResolver.call(
      title: "Aramco refinery erupts in flames in Jizan",
      candidates: candidates, client: stub('{"choice": 1, "reason": "refinery"}')
    )

    assert result.resolved?
    assert_equal @refinery.id, result.entity_id
  end

  test "returns none when the report only mentions the place" do
    result = RegistryEntityResolver.call(
      title: "Nagasaki marks bombing anniversary",
      candidates: [match_for(@port)], client: stub('{"choice": null}')
    )

    assert_not result.resolved?
  end

  # The point of choosing from a list: the model cannot name something that is
  # not in the graph, and an index it invents resolves to nothing rather than to
  # the wrong row.
  test "treats an out-of-range choice as none" do
    result = RegistryEntityResolver.call(
      title: "Something happened", candidates: [match_for(@port)],
      client: stub('{"choice": 7}')
    )

    assert_not result.resolved?
  end

  test "survives unparseable output" do
    result = RegistryEntityResolver.call(
      title: "Something happened", candidates: [match_for(@port)], client: stub("I think it is the port!")
    )

    assert_not result.resolved?
  end

  # A resolver that raises would take the whole sync down; an unresolved
  # candidate is just the pre-1.4 state.
  test "survives a dead client" do
    result = RegistryEntityResolver.call(
      title: "Something happened", candidates: [match_for(@port)], client: ->(_) { nil }
    )

    assert_not result.resolved?
  end

  test "asks nothing when there are no candidates" do
    called = false
    RegistryEntityResolver.call(title: "Anything", candidates: [], client: ->(_) { called = true })

    assert_not called, "no candidates means no model call"
  end

  test "prompt lists candidates by index with their type" do
    prompt = RegistryEntityResolver.prompt_for("Fire at Jizan", [match_for(@port), match_for(@refinery)])

    assert_includes prompt, "0. JIZAN"
    assert_includes prompt, "1. JAZAN"
    assert_includes prompt, "power_plant"
  end
end
