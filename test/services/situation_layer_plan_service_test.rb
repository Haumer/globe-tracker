require "test_helper"

class SituationLayerPlanServiceTest < ActiveSupport::TestCase
  # A curator stub: deterministic, never network-bound.
  class FixedCurator
    attr_reader :neighbors_seen

    def initialize(basis: "heuristic", picks: {}, brief: nil, radius_km: nil, regions: [], related: [])
      @result = SituationLayerCurator::Result.new(
        basis: basis, picks: picks, brief: brief, radius_km: radius_km, regions: regions, related: related
      )
    end

    def call(situation:, available_keys:, neighbors: [])
      @neighbors_seen = neighbors
      @result
    end
  end

  def cluster(key:, title:, lat:, lng:, seen: 1.day.ago)
    record = NewsStoryCluster.create!(
      cluster_key: key, canonical_title: title, event_family: "conflict", event_type: "airstrike",
      verification_status: "single_source", geo_precision: "unknown", cluster_confidence: 0.6,
      source_reliability: 0.6, geo_confidence: 0.0, first_seen_at: 3.days.ago, last_seen_at: seen,
      article_count: 4
    )
    OntologyEvent.create!(
      canonical_key: "news-story-cluster:#{key}", primary_story_cluster: record,
      event_family: "conflict", event_type: "airstrike", last_seen_at: seen,
      latitude: lat, longitude: lng
    )
  end

  def situation(key:, name:, events:, concerns: nil)
    entity = OntologyEntity.create!(
      canonical_key: key, entity_type: "situation", canonical_name: name,
      metadata: { "grouped_by" => "entity", "member_count" => events.size }
    )
    events.each do |event|
      OntologyEventEntity.create!(ontology_event: event, ontology_entity: entity, role: "in_situation")
    end
    if concerns
      OntologyRelationship.create!(source_node: entity, target_node: concerns, relation_type: "concerns",
                                   confidence: 0.8, derived_by: "situation_builder_v1")
    end
    entity
  end

  def place_entity(name: "Kyiv", country: "UA", lat: 50.45, lng: 30.52, radius: nil)
    metadata = { "latitude" => lat, "longitude" => lng }
    metadata["radius_km"] = radius if radius
    OntologyEntity.create!(
      canonical_key: "place:#{name.downcase}", entity_type: "place", canonical_name: name,
      country_code: country, metadata: metadata
    )
  end

  test "returns nil for an unknown situation" do
    assert_nil SituationLayerPlanService.call(situation_id: 999_999, curator: FixedCurator.new)
  end

  test "plans every catalog layer with a bbox around the anchor" do
    place = place_entity
    event = cluster(key: "p1", title: "Strike on the depot", lat: 50.4, lng: 30.5)
    entity = situation(key: "situation:place:1", name: "Kyiv situation", events: [event], concerns: place)

    plan = SituationLayerPlanService.call(situation_id: entity.id, curator: FixedCurator.new)

    assert_equal entity.id, plan[:situation_id]
    assert_equal SituationLayerPlanService::CATALOG.map { |l| l[:key] },
                 plan[:layers].map { |l| l[:key] }

    bbox = plan[:bbox]
    assert_operator bbox[:north], :>, 50.45
    assert_operator bbox[:south], :<, 50.45
    assert_operator bbox[:east], :>, 30.52
    assert_operator bbox[:west], :<, 30.52
    # The default box is ±150 km, ~1.35° of latitude.
    assert_in_delta 1.35, bbox[:north] - 50.45, 0.05
  end

  test "a measured footprint widens the box but the cap holds" do
    place = place_entity(radius: 5_000)
    event = cluster(key: "p2", title: "Quake", lat: 50.4, lng: 30.5)
    entity = situation(key: "situation:place:2", name: "Kyiv situation", events: [event], concerns: place)

    plan = SituationLayerPlanService.call(situation_id: entity.id, curator: FixedCurator.new)

    assert_equal SituationLayerPlanService::MAX_RADIUS_KM, plan[:radius_km]
  end

  test "curated layers start on only when their source is ready" do
    place = place_entity
    event = cluster(key: "p3", title: "Strike", lat: 50.4, lng: 30.5)
    entity = situation(key: "situation:place:3", name: "Kyiv situation", events: [event], concerns: place)

    curator = FixedCurator.new(basis: "ai", picks: {
      "notams" => "airspace matters here",
      "ships" => "irrelevant pick — no AIS key in test"
    })
    plan = SituationLayerPlanService.call(situation_id: entity.id, curator: curator)

    notams = plan[:layers].find { |l| l[:key] == "notams" }
    assert_equal "ready", notams[:status], "static no-fly zones are always servable"
    assert notams[:on_by_default]
    assert_equal "airspace matters here", notams[:reason]

    ships = plan[:layers].find { |l| l[:key] == "ships" }
    assert_not ships[:on_by_default], "a picked layer whose source is #{ships[:status]} must not start on"

    assert_equal "ai", plan[:curated_by]
  end

  test "baseline boundaries need an anchor country and never depend on curation" do
    place = place_entity
    event = cluster(key: "p4", title: "Strike", lat: 50.4, lng: 30.5)
    entity = situation(key: "situation:place:4", name: "Kyiv situation", events: [event], concerns: place)

    plan = SituationLayerPlanService.call(situation_id: entity.id, curator: FixedCurator.new)
    boundaries = plan[:layers].find { |l| l[:key] == "boundaries" }

    assert boundaries[:baseline]
    assert_equal "ready", boundaries[:status]
    assert boundaries[:on_by_default]
    assert_equal 2, boundaries[:sources].size, "districts first, admin1 fallback"
    assert boundaries[:sources].all? { |s| s[:params][:country_codes] == "UA" }
  end

  test "an actor situation with no place gets no boundary sources" do
    event_a = cluster(key: "a1", title: "One", lat: 15.3, lng: 44.2)
    event_b = cluster(key: "a2", title: "Two", lat: 15.4, lng: 44.3)
    entity = situation(key: "situation:actor:5", name: "Houthis situation", events: [event_a, event_b])

    plan = SituationLayerPlanService.call(situation_id: entity.id, curator: FixedCurator.new)
    boundaries = plan[:layers].find { |l| l[:key] == "boundaries" }

    assert_equal "empty", boundaries[:status]
    assert_empty boundaries[:sources]
    assert_not boundaries[:on_by_default]
  end

  test "at most DEFAULT_ON_LIMIT curated layers start on; the rest stay suggested" do
    place = place_entity
    event = cluster(key: "p8", title: "Strike", lat: 50.4, lng: 30.5)
    entity = situation(key: "situation:place:8", name: "Kyiv situation", events: [event], concerns: place)

    # Make four more layers genuinely ready so the cap, not availability,
    # is what limits the defaults.
    MilitaryBase.create!(external_id: "mb1", latitude: 50.0, longitude: 30.0, base_type: "air_force")
    Pipeline.create!(pipeline_id: "pl1", name: "Test line")
    Camera.create!(webcam_id: "cam1", source: "windy", latitude: 50.0, longitude: 30.0, status: "active")
    ConflictEvent.create!(external_id: "ce1", latitude: 50.0, longitude: 30.0, date_start: 1.month.ago)

    curator = FixedCurator.new(basis: "ai", picks: {
      "notams" => "first", "military_bases" => "second", "conflict_events" => "third",
      "infrastructure" => "fourth", "webcams" => "fifth"
    })
    plan = SituationLayerPlanService.call(situation_id: entity.id, curator: curator)
    layers = plan[:layers].index_by { |l| l[:key] }

    on = plan[:layers].reject { |l| l[:baseline] }.select { |l| l[:on_by_default] }.map { |l| l[:key] }
    assert_equal %w[conflict_events military_bases notams], on.sort

    assert_not layers["infrastructure"][:on_by_default]
    assert_equal "fourth", layers["infrastructure"][:reason], "an over-limit pick keeps its reason as a suggestion"
  end

  test "bbox params speak each endpoint's dialect" do
    place = place_entity
    event = cluster(key: "p6", title: "Strike", lat: 50.4, lng: 30.5)
    entity = situation(key: "situation:place:6", name: "Kyiv situation", events: [event], concerns: place)

    plan = SituationLayerPlanService.call(situation_id: entity.id, curator: FixedCurator.new)
    layers = plan[:layers].index_by { |l| l[:key] }

    aircraft = layers["aircraft"][:sources].first[:params]
    assert aircraft.key?(:lamin) && aircraft.key?(:lomax), "flights speak lamin/lomax"

    webcams = layers["webcams"][:sources].first[:params]
    assert webcams.key?(:north) && webcams.key?(:west), "webcams speak compass"

    fires = layers["fires"][:sources].first[:params]
    assert fires.key?(:lamin), "fires are box-scoped server-side now"
    assert fires.key?(:from), "fires are scoped to the situation's window"

    conflict = layers["conflict_events"][:sources].first[:params]
    assert conflict.key?(:from), "UCDP history is bounded, not all-time"
  end

  test "the curator's radius sizes the box" do
    place = place_entity
    event = cluster(key: "r1", title: "Protest downtown", lat: 50.4, lng: 30.5)
    entity = situation(key: "situation:place:r1", name: "Kyiv situation", events: [event], concerns: place)

    plan = SituationLayerPlanService.call(
      situation_id: entity.id,
      curator: FixedCurator.new(basis: "ai", radius_km: 50.0)
    )

    assert_equal 50.0, plan[:radius_km], "story scope beats the geometric default"
    # ±50 km is ~0.45° of latitude.
    assert_in_delta 0.45, plan[:bbox][:north] - 50.45, 0.02
  end

  test "curated regions cross borders: the boundary sources cover their countries too" do
    place = place_entity
    event = cluster(key: "r2", title: "Strikes exchanged", lat: 50.4, lng: 30.5)
    entity = situation(key: "situation:place:r2", name: "Kyiv situation", events: [event], concerns: place)

    regions = [
      { name: "Kyiv Oblast", country_code: "UA", impact: "high" },
      { name: "Gomel", country_code: "BY", impact: "moderate" }
    ]
    plan = SituationLayerPlanService.call(
      situation_id: entity.id,
      curator: FixedCurator.new(basis: "ai", regions: regions, brief: "Two sentences of prose.")
    )

    assert_equal regions, plan[:regions]
    assert_equal "Two sentences of prose.", plan[:brief]

    boundaries = plan[:layers].find { |l| l[:key] == "boundaries" }
    assert boundaries[:sources].all? { |s| s[:params][:country_codes] == "UA,BY" }
  end

  test "an actor situation gains boundary sources when the curator names regions" do
    event_a = cluster(key: "r3", title: "One", lat: 15.3, lng: 44.2)
    event_b = cluster(key: "r4", title: "Two", lat: 15.4, lng: 44.3)
    entity = situation(key: "situation:actor:r3", name: "Houthis situation", events: [event_a, event_b])

    plan = SituationLayerPlanService.call(
      situation_id: entity.id,
      curator: FixedCurator.new(basis: "ai", regions: [{ name: "Sanaa", country_code: "YE", impact: "high" }])
    )
    boundaries = plan[:layers].find { |l| l[:key] == "boundaries" }

    assert_equal "ready", boundaries[:status]
    assert boundaries[:sources].all? { |s| s[:params][:country_codes] == "YE" }
  end

  test "related keeps only situations actually on the board, and the curator sees its neighbors" do
    place = place_entity
    event_a = cluster(key: "n1", title: "Strike", lat: 50.4, lng: 30.5)
    entity = situation(key: "situation:place:n1", name: "Kyiv situation", events: [event_a], concerns: place)

    other_place = place_entity(name: "Odesa", lat: 46.48, lng: 30.72)
    event_b = cluster(key: "n2", title: "Port hit", lat: 46.5, lng: 30.7)
    other = situation(key: "situation:place:n2", name: "Odesa situation", events: [event_b], concerns: other_place)

    curator = FixedCurator.new(basis: "ai", related: [
      { id: other.id, reason: "same campaign" },
      { id: 999_999, reason: "hallucinated" }
    ])
    plan = SituationLayerPlanService.call(situation_id: entity.id, curator: curator)

    assert_equal 1, plan[:related].size
    row = plan[:related].first
    assert_equal other.id, row[:id]
    assert_equal "Odesa", row[:name]
    assert_equal "same campaign", row[:reason]
    assert_in_delta 442, row[:distance_km], 15
    assert row[:anchor][:lat], "the client draws the association between the two anchors"

    assert_equal [other.id], curator.neighbors_seen.map { |n| n[:id] },
                 "the curator is offered the board's other situations, never itself"
  end

  test "fires window matches the situation window and conflict gets a year of context" do
    place = place_entity
    event = cluster(key: "p7", title: "Strike", lat: 50.4, lng: 30.5)
    entity = situation(key: "situation:place:7", name: "Kyiv situation", events: [event], concerns: place)

    now = Time.current
    plan = SituationLayerPlanService.new(
      situation: SituationLayerPlanService.board(now: now)[:situations].find { |r| r[:id] == entity.id },
      curator: FixedCurator.new, now: now
    ).call
    layers = plan[:layers].index_by { |l| l[:key] }

    fires_from = Time.parse(layers["fires"][:sources].first[:params][:from])
    assert_in_delta (now - SituationLayerPlanService::FIRES_WINDOW).to_f, fires_from.to_f, 60

    conflict_from = Time.parse(layers["conflict_events"][:sources].first[:params][:from])
    assert_in_delta (now - SituationLayerPlanService::CONFLICT_WINDOW).to_f, conflict_from.to_f, 60
  end
end
