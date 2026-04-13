require "test_helper"

class SituationSurfaceServiceTest < ActiveSupport::TestCase
  test "separates attention score from severity class" do
    payload = {
      zones: [
        {
          cell_key: "34.0,50.0",
          lat: 35.0,
          lng: 51.0,
          situation_name: "Iran Theater",
          theater: "Middle East / Iran War",
          pulse_score: 91,
          count_24h: 83,
          source_count: 39,
          story_count: 82,
          cross_layer_signals: { verified_strike_reports_7d: 12 },
          top_headlines: ["Iran war live: Israeli missile strikes hit facilities near Tehran"],
        },
        {
          cell_key: "52.0,-8.0",
          lat: 53.0,
          lng: -7.0,
          situation_name: "United Kingdom",
          theater: "Europe",
          pulse_score: 91,
          count_24h: 10,
          source_count: 5,
          story_count: 6,
          cross_layer_signals: { thermal_detections_7d: 964 },
          top_headlines: ["Fuel protests continue in Ireland as demonstrators blockade refinery supply routes"],
        },
      ],
      strategic_situations: [],
      hex_cells: [
        { zone_key: "34.0,50.0", vertices: [[34.0, 49.0], [35.5, 49.7], [35.2, 52.0], [33.6, 51.4]] },
        { zone_key: "52.0,-8.0", vertices: [[52.0, -9.5], [53.5, -9.0], [54.0, -7.0], [53.0, -5.5], [51.8, -6.5], [51.5, -8.5]] },
      ],
    }

    result = SituationSurfaceService.build(conflict_payload: payload, include_live_events: false, now: Time.zone.parse("2026-04-11 12:00:00"))
    surfaces = result.fetch(:surfaces)

    iran = surfaces.find { |surface| surface[:id] == "zone:34.0,50.0" }
    ireland = surfaces.find { |surface| surface[:id] == "zone:52.0,-8.0" }
    national_iran = surfaces.find { |surface| surface[:id] == "system:iran" }

    assert_equal "kinetic_conflict", iran[:situation_class]
    assert_equal "critical", iran[:severity_tier]
    assert_equal "countries", iran[:boundary_ref][:dataset]
    assert_equal "Iran", iran[:boundary_ref][:name]
    assert_nil iran[:geometry]
    assert_nil ireland
    assert_equal "national", national_iran[:scope]
    assert_equal "Iran", national_iran[:boundary_ref][:name]
  end

  test "builds chokepoint corridor surfaces from strategic situations" do
    payload = {
      zones: [],
      strategic_situations: [
        {
          id: "strategic:hormuz",
          node_id: "hormuz",
          name: "Strait of Hormuz",
          status: "critical",
          strategic_score: 96,
          source_count: 18,
          direct_cluster_count: 6,
          pressure_summary: "Direct reporting indicates shipping pressure through Hormuz.",
        },
      ],
      hex_cells: [],
    }

    result = SituationSurfaceService.build(conflict_payload: payload, include_live_events: false)
    surface = result.fetch(:surfaces).find { |candidate| candidate[:id] == "strategic:hormuz" }

    assert_equal "strategic_chokepoint", surface[:situation_class]
    assert_equal "critical", surface[:severity_tier]
    assert_equal "corridor", surface[:scope]
    assert_equal "curated_corridor", surface[:geometry][:source]
    assert surface[:geometry][:rings].first.size >= 4
  end

  test "adds ontology theater-pressure corridor surfaces without duplicating strategic payload" do
    theater = OntologyEntity.create!(
      canonical_key: "theater:test-war",
      entity_type: "theater",
      canonical_name: "Test War",
      metadata: {},
    )
    bosphorus = OntologyEntity.create!(
      canonical_key: "corridor:chokepoint:bosphorus",
      entity_type: "corridor",
      canonical_name: "Bosphorus Strait",
      metadata: { "latitude" => 41.12, "longitude" => 29.05 },
    )
    airport = OntologyEntity.create!(
      canonical_key: "airport:test-bosphorus",
      entity_type: "airport",
      canonical_name: "Test Bosphorus Airport",
      metadata: { "latitude" => 41.1, "longitude" => 29.1 },
    )
    pressure = OntologyRelationship.create!(
      source_node: theater,
      target_node: bosphorus,
      relation_type: "theater_pressure",
      confidence: 0.95,
      fresh_until: 1.hour.from_now,
      derived_by: "test",
      explanation: "Test War is exerting strategic pressure on Bosphorus Strait",
      metadata: { "cluster_count" => 4, "total_sources" => 12, "local_cluster_count" => 3 },
    )
    cluster = NewsStoryCluster.create!(
      cluster_key: "cluster:test-bosphorus",
      canonical_title: "Shipping pressure rises in the Bosphorus Strait",
      content_scope: "core",
      event_family: "conflict",
      event_type: "military_activity",
      location_name: "Bosphorus Strait",
      latitude: 41.12,
      longitude: 29.05,
      geo_precision: "point",
      first_seen_at: 1.hour.ago,
      last_seen_at: 10.minutes.ago,
      article_count: 3,
      source_count: 3,
      cluster_confidence: 0.84,
      verification_status: "multi_source",
      source_reliability: 0.78,
      geo_confidence: 0.82,
    )
    OntologyRelationshipEvidence.create!(
      ontology_relationship: pressure,
      evidence: cluster,
      evidence_role: "local_story",
      confidence: 0.84,
    )
    OntologyRelationship.create!(
      source_node: bosphorus,
      target_node: airport,
      relation_type: "downstream_exposure",
      confidence: 0.8,
      fresh_until: 1.hour.from_now,
      derived_by: "test",
      explanation: "Bosphorus pressure leaves Test Bosphorus Airport exposed downstream",
      metadata: {},
    )

    result = SituationSurfaceService.build(conflict_payload: { zones: [], strategic_situations: [], hex_cells: [] }, include_live_events: false)
    surface = result.fetch(:surfaces).find { |candidate| candidate[:id] == "ontology:pressure:corridor:chokepoint:bosphorus" }

    assert_equal "Bosphorus Strait", surface[:label]
    assert_equal "strategic_chokepoint", surface[:situation_class]
    assert_equal "high", surface[:severity_tier]
    assert_equal "ontology_theater_pressure", surface[:geometry][:source]
    assert_equal pressure.id, surface.dig(:ontology, :relationship_id)
    assert_equal 1, surface.dig(:ontology, :downstream_exposure_count)
    assert_equal({ kind: "chokepoint", id: "Bosphorus Strait" }, surface.dig(:ontology, :request))

    duplicate_payload = {
      zones: [],
      strategic_situations: [
        {
          id: "strategic:bosphorus",
          node_id: "bosphorus",
          name: "Bosphorus Strait",
          status: "critical",
          strategic_score: 90,
          source_count: 8,
          direct_cluster_count: 3,
        },
      ],
      hex_cells: [],
    }
    duplicate_result = SituationSurfaceService.build(conflict_payload: duplicate_payload, include_live_events: false)

    assert_includes duplicate_result.fetch(:surfaces).map { |candidate| candidate[:id] }, "strategic:bosphorus"
    assert_not_includes duplicate_result.fetch(:surfaces).map { |candidate| candidate[:id] }, "ontology:pressure:corridor:chokepoint:bosphorus"
  end

  test "does not promote strategic-only ontology pressure to a surface" do
    theater = OntologyEntity.create!(
      canonical_key: "theater:test-middle-east",
      entity_type: "theater",
      canonical_name: "Test Middle East",
      metadata: {},
    )
    suez = OntologyEntity.create!(
      canonical_key: "corridor:chokepoint:suez",
      entity_type: "corridor",
      canonical_name: "Suez Canal",
      metadata: { "latitude" => 30.46, "longitude" => 32.34 },
    )
    OntologyRelationship.create!(
      source_node: theater,
      target_node: suez,
      relation_type: "theater_pressure",
      confidence: 0.8,
      fresh_until: 1.hour.from_now,
      derived_by: "test",
      explanation: "Test Middle East is exerting strategic pressure on Suez Canal",
      metadata: { "cluster_count" => 9, "total_sources" => 30, "local_cluster_count" => 0, "strategic_target" => true },
    )

    result = SituationSurfaceService.build(conflict_payload: { zones: [], strategic_situations: [], hex_cells: [] }, include_live_events: false)

    assert_not_includes result.fetch(:surfaces).map { |candidate| candidate[:id] }, "ontology:pressure:corridor:chokepoint:suez"
  end

  test "skips duplicate zone surface when a strategic pressure surface already covers the corridor" do
    payload = {
      zones: [
        {
          cell_key: "26.0,56.0",
          lat: 26.0,
          lng: 56.0,
          situation_name: "Strait of Hormuz",
          theater: "Middle East / Iran War",
          pulse_score: 81,
          attention_state: "strategic_pressure",
          count_24h: 9,
          source_count: 8,
          story_count: 17,
          cross_layer_signals: {},
          top_headlines: ["Shipping pressure around the Strait of Hormuz remains elevated"],
        },
      ],
      strategic_situations: [
        {
          id: "strategic:hormuz",
          node_id: "hormuz",
          name: "Strait of Hormuz",
          status: "critical",
          strategic_score: 93,
          source_count: 8,
          direct_cluster_count: 4,
          pressure_summary: "Direct reporting indicates chokepoint pressure.",
        },
      ],
      hex_cells: [
        { zone_key: "26.0,56.0", vertices: [[25.5, 55.2], [26.8, 55.3], [27.0, 57.0], [25.7, 57.2]] },
      ],
    }

    result = SituationSurfaceService.build(conflict_payload: payload, include_live_events: false)
    ids = result.fetch(:surfaces).map { |surface| surface[:id] }

    assert_includes ids, "strategic:hormuz"
    assert_not_includes ids, "zone:26.0,56.0"
  end

  test "does not promote diplomacy-only reporting to a surface" do
    payload = {
      zones: [
        {
          cell_key: "33.0,73.0",
          lat: 33.7,
          lng: 73.0,
          situation_name: "Pakistan-Afghanistan",
          theater: "South Asia",
          pulse_score: 79,
          count_24h: 6,
          source_count: 4,
          story_count: 5,
          cross_layer_signals: {},
          top_headlines: [
            "Pakistan hosts Afghanistan envoy for talks on border negotiations and regional diplomacy",
          ],
        },
      ],
      strategic_situations: [],
      hex_cells: [],
    }

    result = SituationSurfaceService.build(conflict_payload: payload, include_live_events: false)

    assert_empty result.fetch(:surfaces)
  end

  test "does not render public-order reporting cells without a real region" do
    payload = {
      zones: [
        {
          cell_key: "52.0,-8.0",
          lat: 53.0,
          lng: -7.0,
          situation_name: "United Kingdom",
          theater: "Europe",
          pulse_score: 78,
          count_24h: 10,
          source_count: 5,
          story_count: 6,
          cross_layer_signals: {},
          top_headlines: ["Irish fuel protests continue as demonstrators blockade refinery supply routes"],
        },
      ],
      strategic_situations: [],
      hex_cells: [
        { zone_key: "52.0,-8.0", vertices: [[52.0, -9.5], [53.5, -9.0], [54.0, -7.0], [53.0, -5.5], [51.8, -6.5], [51.5, -8.5]] },
      ],
    }

    result = SituationSurfaceService.build(conflict_payload: payload, include_live_events: false)

    assert_empty result.fetch(:surfaces)
  end

  test "promotes recent verified strike geolocations to regional surfaces" do
    now = Time.zone.parse("2026-04-11 12:00:00")
    GeoconfirmedEvent.create!(
      external_id: "gc-northern-israel-1",
      map_region: "iran",
      title: "11 APR 2026",
      latitude: 33.12,
      longitude: 35.43,
      event_time: now - 2.hours,
      posted_at: now - 1.hour,
      fetched_at: now,
      source_urls: ["https://example.test/source"],
      geolocation_urls: ["https://example.test/geolocation"],
    )
    GeoconfirmedEvent.create!(
      external_id: "gc-northern-israel-2",
      map_region: "iran",
      title: "11 APR 2026 follow-up",
      latitude: 33.2,
      longitude: 35.41,
      event_time: now - 3.hours,
      posted_at: now - 2.hours,
      fetched_at: now,
    )

    result = SituationSurfaceService.build(conflict_payload: { zones: [], strategic_situations: [], hex_cells: [] }, include_live_events: true, now: now)
    surface = result.fetch(:surfaces).find { |candidate| candidate[:id] == "verified-strike:northern-israel" }

    assert_equal "Northern Israel verified strike reports", surface[:label]
    assert_equal "kinetic_conflict", surface[:situation_class]
    assert_equal "high", surface[:severity_tier]
    assert_equal "admin1", surface[:boundary_ref][:dataset]
    assert_equal "IL-Z", surface[:boundary_ref][:iso_3166_2]
    assert_equal 2, surface[:story_count]
    assert_equal "geoconfirmed", surface.dig(:source, :source_type)
  end

  test "only promotes the strongest critical internet outage to situation surfaces" do
    outages = [
      { code: "NA", name: "Namibia", score: 1_000_000.0, eventCount: 3, level: "critical" },
      { code: "BH", name: "Bahrain", score: 640_000.0, eventCount: 1, level: "critical" },
      { code: "ID", name: "Indonesia", score: 30_000.0, eventCount: 1, level: "severe" },
      { code: "NG", name: "Nigeria", score: 3_000.0, eventCount: 4, level: "moderate" },
      { code: "OM", name: "Oman", score: 2_500.0, eventCount: 1, level: "moderate" },
      { code: "XX", name: "Extra", score: 20_000.0, eventCount: 1, level: "severe" },
    ]

    SituationSurfaceService.stub(:outage_summary, outages) do
      surfaces = SituationSurfaceService.send(:build_outage_surfaces, now: Time.zone.parse("2026-04-11 12:00:00"))

      assert_equal ["outage:NA"], surfaces.map { |surface| surface[:id] }
      assert_empty surfaces.select { |surface| surface[:id] == "outage:BH" }
      assert_empty surfaces.select { |surface| surface[:id] == "outage:ID" }
    end
  end

  test "uses real boundary refs instead of synthetic grid geometry" do
    payload = {
      zones: [
        {
          cell_key: "50.0,30.0",
          lat: 50.0,
          lng: 30.0,
          situation_name: "Kyiv Region",
          theater: "Russia-Ukraine War",
          pulse_score: 68,
          count_24h: 4,
          source_count: 4,
          story_count: 4,
          cross_layer_signals: {},
          top_headlines: ["Russian drone strikes continue around Kyiv region"],
        },
        {
          cell_key: "32.0,34.0",
          lat: 32.0,
          lng: 34.0,
          situation_name: "Israel-Palestine",
          theater: "Middle East / Iran War",
          pulse_score: 68,
          count_24h: 4,
          source_count: 4,
          story_count: 4,
          cross_layer_signals: {},
          top_headlines: ["Hezbollah rocket from Lebanon strikes Safed"],
        },
      ],
      strategic_situations: [],
      hex_cells: [
        { zone_key: "50.0,30.0", vertices: [[50.0, 30.0], [51.0, 30.5], [50.5, 31.5]] },
        { zone_key: "32.0,34.0", vertices: [[32.0, 34.0], [33.0, 34.5], [32.5, 35.5]] },
      ],
    }

    result = SituationSurfaceService.build(conflict_payload: payload, include_live_events: false)
    kyiv = result.fetch(:surfaces).find { |surface| surface[:id] == "zone:50.0,30.0" }
    northern_israel = result.fetch(:surfaces).find { |surface| surface[:id] == "zone:32.0,34.0" }

    assert_equal "admin1", kyiv[:boundary_ref][:dataset]
    assert_equal "UA-32", kyiv[:boundary_ref][:iso_3166_2]
    assert_nil kyiv[:geometry]
    assert_equal "admin1", northern_israel[:boundary_ref][:dataset]
    assert_equal "IL-Z", northern_israel[:boundary_ref][:iso_3166_2]
    assert_nil northern_israel[:geometry]
  end
end
