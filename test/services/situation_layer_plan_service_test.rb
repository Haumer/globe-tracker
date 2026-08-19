require "test_helper"

class SituationLayerPlanServiceTest < ActiveSupport::TestCase
  # A curator stub: deterministic, never network-bound.
  class FixedCurator
    def initialize(basis: "heuristic", picks: {})
      @result = SituationLayerCurator::Result.new(basis: basis, picks: picks)
    end

    def call(situation:, available_keys:)
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
