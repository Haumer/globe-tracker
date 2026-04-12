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
    assert_equal "public_order", ireland[:situation_class]
    assert_equal "moderate", ireland[:severity_tier]
    assert_equal "local", ireland[:scope]
    assert_equal "Ireland fuel protests", ireland[:label]
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
