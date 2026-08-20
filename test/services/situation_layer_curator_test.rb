require "test_helper"

class SituationLayerCuratorTest < ActiveSupport::TestCase
  ALL_KEYS = SituationLayerPlanService::CATALOG.reject { |l| l[:baseline] }.map { |l| l[:key] }

  # The curator builds a real OpenAI client whenever OPENAI_API_KEY is present,
  # and a developer's .env makes it present. These tests must be deterministic
  # on any machine, so the key is hidden for their duration.
  setup do
    @openai_key = ENV.delete("OPENAI_API_KEY")
  end

  teardown do
    ENV["OPENAI_API_KEY"] = @openai_key if @openai_key
  end

  def situation(name: "Kyiv", entity_type: "place", country: "UA", types: ["airstrike"], headlines: ["Strike hits depot"])
    {
      id: 1,
      name: name,
      member_count: types.size,
      last_seen_at: "2026-08-18T00:00:00Z",
      concerns: { entity_type: entity_type, country_code: country, name: name },
      members: types.each_with_index.map do |type, index|
        { event_type: type, headline: headlines[index] || "Headline #{index}" }
      end
    }
  end

  class FakeClient
    def initialize(content)
      @content = content
    end

    def call(system:, user:)
      @content
    end
  end

  class ExplodingClient
    def call(system:, user:)
      raise Net::ReadTimeout
    end
  end

  test "model picks are filtered to the available catalog" do
    client = FakeClient.new('{"layers": [{"key": "fires", "reason": "corroborates strikes"}, {"key": "made_up", "reason": "x"}]}')
    result = SituationLayerCurator.call(situation: situation, available_keys: ALL_KEYS, client: client)

    assert_equal "ai", result.basis
    assert_equal({ "fires" => "corroborates strikes" }, result.picks)
  end

  test "a broken model response falls back to the rules, never raises" do
    client = FakeClient.new("I think you should look at everything!")
    result = SituationLayerCurator.call(situation: situation, available_keys: ALL_KEYS, client: client)

    assert_equal "heuristic", result.basis
  end

  test "a network failure falls back to the rules" do
    result = SituationLayerCurator.call(situation: situation, available_keys: ALL_KEYS, client: ExplodingClient.new)

    assert_equal "heuristic", result.basis
    assert result.picks.key?("fires"), "an airstrike situation should default the heat layer on"
  end

  test "heuristics read the story: maritime stories get ships, quakes get the instrument record" do
    maritime = SituationLayerCurator.call(
      situation: situation(name: "Strait of Hormuz", entity_type: "corridor", types: ["maritime_incident"]),
      available_keys: ALL_KEYS
    )
    assert maritime.picks.key?("ships")
    assert maritime.picks.key?("infrastructure")

    quake = SituationLayerCurator.call(
      situation: situation(name: "Granada earthquake", entity_type: "hazard_occurrence", types: ["earthquake"]),
      available_keys: ALL_KEYS
    )
    assert quake.picks.key?("earthquakes")
    assert quake.picks.key?("webcams"), "hazards are exactly when someone points a camera"
    assert_not quake.picks.key?("military_bases")
  end

  test "heuristic picks respect availability" do
    result = SituationLayerCurator.call(
      situation: situation(types: ["airstrike"]),
      available_keys: ["conflict_events"]
    )

    assert_equal ["conflict_events"], result.picks.keys
  end

  test "pick count is capped" do
    client = FakeClient.new({ layers: ALL_KEYS.map { |k| { key: k, reason: "r" } } }.to_json)
    result = SituationLayerCurator.call(situation: situation, available_keys: ALL_KEYS, client: client)

    assert_operator result.picks.size, :<=, SituationLayerCurator::MAX_PICKS
  end

  test "the full judgement parses: brief, clamped radius, graded regions, related from the board" do
    neighbors = [{ id: 42, name: "Bandar Abbas port", distance_km: 120.0, country: "IR" }]
    client = FakeClient.new({
      brief: "Strikes continue around the strait. Watch tanker transits.",
      radius_km: 5_000,
      layers: [{ key: "fires", reason: "corroborates" }],
      regions: [
        { name: "Hormozgan", country_code: "ir", impact: "high" },
        { name: "Dubai", country_code: "AE", impact: "catastrophic" },
        { name: "", country_code: "AE", impact: "high" }
      ],
      related: [{ id: 42, reason: "same theater" }, { id: 999, reason: "not on the board" }]
    }.to_json)

    result = SituationLayerCurator.call(
      situation: situation, available_keys: ALL_KEYS, neighbors: neighbors, client: client
    )

    assert_equal "Strikes continue around the strait. Watch tanker transits.", result.brief
    assert_equal SituationLayerCurator::MAX_RADIUS_KM, result.radius_km, "an absurd radius is clamped, not trusted"
    assert_equal [{ name: "Hormozgan", country_code: "IR", impact: "high" }], result.regions,
                 "unknown grades and empty names are dropped"
    assert_equal [{ id: 42, reason: "same theater" }], result.related,
                 "related may only name situations from the given list"
  end

  test "the heuristic path fabricates no judgement" do
    result = SituationLayerCurator.call(situation: situation, available_keys: ALL_KEYS)

    assert_equal "heuristic", result.basis
    assert_nil result.brief
    assert_nil result.radius_km, "scope falls back to geometry in the plan service"
    assert_empty result.regions
    assert_empty result.related
  end
end
