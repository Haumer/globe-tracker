require "test_helper"

class RegistryNameIndexTest < ActiveSupport::TestCase
  # A corpus is required for the capitalisation test to have anything to learn
  # from; these stand in for the recent cluster titles.
  CORPUS = [
    "Iran moves to block shipments from Strait of Hormuz",
    "Houthis attack Saudi Aramco Jazan refinery",
    "Officials say police just want a safe outcome that works",
    "Report says police detained protesters",
  ].freeze

  def index
    @index ||= RegistryNameIndex.new(corpus: CORPUS)
  end

  def corridor(key, name)
    OntologyEntity.create!(canonical_key: key, entity_type: "corridor", canonical_name: name)
  end

  test "resolves a corridor named in a headline" do
    corridor("corridor:chokepoint:hormuz", "Strait of Hormuz")

    matches = index.match("Iran moves to block shipments from Strait of Hormuz")

    assert_equal ["Strait of Hormuz"], matches.map(&:entity_name)
    assert matches.first.confident?, "a corridor match is the high-precision tier"
  end

  test "resolves a corridor through a seeded short-form alias" do
    entity = corridor("corridor:chokepoint:hormuz", "Strait of Hormuz")
    OntologyEntityAlias.create!(ontology_entity: entity, name: "Hormuz", alias_type: "short_form")

    matches = index.match("Gulf states should make a deal with Iran on Hormuz")

    assert_equal ["Strait of Hormuz"], matches.map(&:entity_name),
      "the 64 clusters saying only Hormuz are the whole point of 1.3"
  end

  # The defect the whole v3 branch exists to stop, one layer out: the masthead is
  # text like any other, and matching it links a story to wherever the paper is.
  test "ignores the publisher suffix" do
    OntologyEntity.create!(canonical_key: "port:bkk", entity_type: "port", canonical_name: "BANGKOK")

    matches = index.match("New Zealand PM open to referendum on electoral system - Bangkok Post")

    assert_empty matches, "the publisher must not be matched as an asset"
  end

  # Registry rows whose names are English words: matching them is how a story
  # about police reached a port called POLICE.
  test "rejects a registry name that is a common word" do
    OntologyEntity.create!(canonical_key: "port:pol", entity_type: "port", canonical_name: "POLICE")

    assert_empty index.match("Report says police detained protesters")
  end

  test "rejects a name whose every token is a category word" do
    OntologyEntity.create!(canonical_key: "base:generic", entity_type: "military_base", canonical_name: "Military Camp")
    # Give "military" and "camp" the spread of category words.
    30.times { |i| OntologyEntity.create!(canonical_key: "base:#{i}", entity_type: "military_base", canonical_name: "Camp Site #{i} Military") }

    assert_empty index.match("Houthis Claim Attack on Yemeni Military Camp"),
      "a name made only of category words describes a kind of thing, not one thing"
  end

  test "rejects a surface that names more than one entity" do
    OntologyEntity.create!(canonical_key: "port:spring1", entity_type: "port", canonical_name: "Springfield")
    OntologyEntity.create!(canonical_key: "port:spring2", entity_type: "power_plant", canonical_name: "Springfield")

    assert_empty index.match("Fire reported in Springfield overnight")
  end

  test "does not treat a country name as a registry asset" do
    OntologyEntity.create!(canonical_key: "country:fra", entity_type: "country",
                           canonical_name: "France", country_code: "FR")
    OntologyEntity.create!(canonical_key: "power-plant:fra", entity_type: "power_plant", canonical_name: "France")

    assert_empty index.match("Talks continue as France weighs its response")
  end

  # A bare toponym proves a place was mentioned, not that its port was involved.
  # Separating those two is Phase 1.4's job, so these stay candidates.
  test "a settlement-named asset is a candidate, not a confident match" do
    OntologyEntity.create!(canonical_key: "port:nagasaki", entity_type: "port", canonical_name: "NAGASAKI")

    matches = index.match("Taiwan representative skips Nagasaki atomic bombing anniversary")

    assert_equal ["NAGASAKI"], matches.map(&:entity_name)
    assert_not matches.first.confident?, "a story about the city is not a story about the port"
  end

  test "a facility-named asset is a confident match" do
    OntologyEntity.create!(canonical_key: "port:kharg", entity_type: "port",
                           canonical_name: "KHARG ISLAND OIL TERMINAL")
    20.times { |i| OntologyEntity.create!(canonical_key: "port:t#{i}", entity_type: "port", canonical_name: "Site #{i} Terminal") }

    matches = index.match("Iran's Kharg Island oil terminal idled by US blockade")

    assert matches.first.confident?, "a trailing facility word marks the name as a facility"
  end

  test "prefers the longest matching surface" do
    corridor("corridor:chokepoint:hormuz", "Strait of Hormuz")
    OntologyEntity.create!(canonical_key: "power-plant:hormuz", entity_type: "power_plant", canonical_name: "Hormuz")

    matches = index.match("Tankers rerouted around the Strait of Hormuz")

    assert_equal ["Strait of Hormuz"], matches.map(&:entity_name),
      "one mention of one place must not be counted twice"
  end
end
