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
    client = FakeClient.new('{"layers": [{"key": "conflict_events", "reason": "corroborates strikes"}, {"key": "made_up", "reason": "x"}]}')
    result = SituationLayerCurator.call(situation: situation, available_keys: ALL_KEYS, client: client)

    assert_equal "ai", result.basis
    assert_equal({ "conflict_events" => "corroborates strikes" }, result.picks)
  end

  test "a broken model response falls back to the rules, never raises" do
    client = FakeClient.new("I think you should look at everything!")
    result = SituationLayerCurator.call(situation: situation, available_keys: ALL_KEYS, client: client)

    assert_equal "heuristic", result.basis
  end

  test "a network failure falls back to the rules" do
    result = SituationLayerCurator.call(situation: situation, available_keys: ALL_KEYS, client: ExplodingClient.new)

    assert_equal "heuristic", result.basis
    assert result.picks.key?("conflict_events"), "an airstrike situation should default the conflict record on"
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
    assert_not quake.picks.key?("conflict_events")
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

  # A situation with everything the composition can draw on, so tests can
  # exercise the module-data guards one at a time by removing pieces.
  def rich_situation(**overrides)
    situation.merge(
      article_count: 54, source_count: 27, tier: "corroborated",
      first_seen_at: "2026-08-20T14:00:00Z", last_seen_at: "2026-08-22T09:00:00Z",
      figures: { "killed" => [ { t: "2026-08-20T15:00:00Z", value: 20 },
                               { t: "2026-08-22T08:00:00Z", value: 132, qualifier: "at_least" } ] },
      attribution: [ { actor: "Iran", reports: 8, sources: 6 },
                     { actor: "United States", reports: 4, sources: 3 } ],
      timeline: { bucket: "hour", first_at: "2026-08-20T14:10:00Z",
                  points: [ { t: "2026-08-20T14:00:00Z", articles: 6, new_sources: 4 } ] },
      sources: { total: 27, countries: 9, top: [ { name: "Stuff", country: "nz", reports: 7 } ] },
      facts: { pairs: [ { from: "Iran", to: "United States", count: 3 } ],
               kinds: [ { kind: "airstrike", count: 3 } ] },
      **overrides
    )
  end

  def composition_json(extra_modules: [], **overrides)
    {
      "layers" => [],
      "composition" => {
        "treatment" => "dossier",
        "angle" => "toll",
        "lead" => "The toll climbed from 20 to at least 132 in two days",
        "dek" => "Coverage from 27 outlets tracks a rising count.",
        "modules" => [
          { "kind" => "figures_chart", "metric" => "killed", "emphasis" => "hero",
            "title" => "The toll passed 100 as crews reached the rubble",
            "caption" => "Each dot is one outlet's figure",
            "annotations" => [ { "t" => "2026-08-21T10:00:00Z", "text" => "crews reach the collapsed blocks" },
                                { "t" => "2026-08-21T12:00:00Z", "text" => "toll passes 100" } ] },
          *extra_modules
        ]
      }.merge(overrides)
    }.to_json
  end

  test "a valid composition parses with its written strings intact" do
    client = FakeClient.new(composition_json)
    result = SituationLayerCurator.call(situation: rich_situation, available_keys: ALL_KEYS, client: client)

    composition = result.composition
    assert_equal "dossier", composition[:treatment]
    assert_equal "The toll climbed from 20 to at least 132 in two days", composition[:lead]
    module_row = composition[:modules].first
    assert_equal "figures_chart", module_row[:kind]
    assert_equal "hero", module_row[:emphasis]
    assert_equal "killed", module_row[:metric]
    assert_equal [ { t: "2026-08-21T10:00:00Z", text: "crews reach the collapsed blocks" } ],
      module_row[:annotations],
      "the rounded-milestone annotation carries a number not in the payload and is dropped alone"
  end

  test "modules without their data are dropped: no figures metric, no chart" do
    client = FakeClient.new(composition_json(extra_modules: [
      { "kind" => "figures_chart", "metric" => "injured", "emphasis" => "support", "title" => "x" },
      { "kind" => "invented_module", "emphasis" => "support" }
    ]))
    result = SituationLayerCurator.call(situation: rich_situation, available_keys: ALL_KEYS, client: client)

    kinds = result.composition[:modules].map { |m| [ m[:kind], m[:metric] ] }
    assert_equal [ [ "figures_chart", "killed" ] ], kinds,
      "the injured series does not exist in the payload and invented kinds are not in the vocabulary"
  end

  test "attribution module is dropped when outlets do not disagree" do
    client = FakeClient.new(composition_json(extra_modules: [
      { "kind" => "attribution_split", "emphasis" => "support", "title" => "Who names whom" }
    ]))
    result = SituationLayerCurator.call(
      situation: rich_situation(attribution: nil), available_keys: ALL_KEYS, client: client)

    assert_equal %w[figures_chart], result.composition[:modules].map { |m| m[:kind] }
  end

  test "only one module keeps hero emphasis" do
    client = FakeClient.new(composition_json(extra_modules: [
      { "kind" => "attention_timeline", "emphasis" => "hero", "title" => "Coverage spiked" }
    ]))
    result = SituationLayerCurator.call(situation: rich_situation, available_keys: ALL_KEYS, client: client)

    assert_equal %w[hero support], result.composition[:modules].map { |m| m[:emphasis] }
  end

  test "an invented number rejects the string that carries it" do
    client = FakeClient.new(composition_json(
      "lead" => "At least 999 dead in the collapse"))
    result = SituationLayerCurator.call(situation: rich_situation, available_keys: ALL_KEYS, client: client)

    assert_nil result.composition, "a composition whose lead invents a figure is no composition"
  end

  test "small numbers pass the gate: day counts are arithmetic, not new claims" do
    client = FakeClient.new(composition_json(
      "lead" => "Day 3 of the recovery and the count is still moving"))
    result = SituationLayerCurator.call(situation: rich_situation, available_keys: ALL_KEYS, client: client)

    assert_equal "Day 3 of the recovery and the count is still moving", result.composition[:lead]
  end

  test "a note carries no modules, whatever the model attached" do
    client = FakeClient.new(composition_json(
      "treatment" => "note",
      "upgrade" => "A second outlet on the strikes upgrades this to corroborated"))
    result = SituationLayerCurator.call(situation: rich_situation, available_keys: ALL_KEYS, client: client)

    assert_equal "note", result.composition[:treatment]
    assert_equal [], result.composition[:modules]
    assert_match(/second outlet/, result.composition[:upgrade])
  end

  test "the full judgement parses: brief, clamped radius, graded regions, related from the board" do
    neighbors = [{ id: 42, name: "Bandar Abbas port", distance_km: 120.0, country: "IR" }]
    client = FakeClient.new({
      brief: "Strikes continue around the strait. Watch tanker transits.",
      radius_km: 5_000,
      layers: [{ key: "conflict_events", reason: "corroborates" }],
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
  # The board arrives named after whichever registry entity its reports keyed
  # on, which is often not the story: the live board filed the Nepal-China
  # floods under "19 km NW of Fuji, China", an earthquake epicentre.
  test "the composition carries a name for the situation" do
    client = FakeClient.new(composition_json("title" => "Nepal-China border floods"))

    result = SituationLayerCurator.call(situation: rich_situation, available_keys: ALL_KEYS, client: client)

    assert_equal "Nepal-China border floods", result.composition[:title]
  end

  test "a title written as a sentence is refused rather than truncated" do
    client = FakeClient.new(composition_json(
      "title" => "Floods and a glacier collapse near the border have killed hundreds of people this week"
    ))

    result = SituationLayerCurator.call(situation: rich_situation, available_keys: ALL_KEYS, client: client)

    assert_nil result.composition[:title], "the keyed name is the safe fallback, not half a sentence"
    assert_equal "dossier", result.composition[:treatment], "the rest of the composition survives"
  end

  test "a title stating a figure the payload does not hold is refused" do
    client = FakeClient.new(composition_json("title" => "Border floods kill 4000"))

    result = SituationLayerCurator.call(situation: rich_situation, available_keys: ALL_KEYS, client: client)

    assert_nil result.composition[:title], "a title is a composed string and may not introduce a number"
  end

  test "a title keeps a figure the payload does hold" do
    client = FakeClient.new(composition_json("title" => "Border floods kill 132"))

    result = SituationLayerCurator.call(situation: rich_situation, available_keys: ALL_KEYS, client: client)

    assert_equal "Border floods kill 132", result.composition[:title]
  end
end
