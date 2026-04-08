require "test_helper"

class Api::ConflictEventsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @event = ConflictEvent.create!(
      external_id: 10001,
      conflict_name: "Test Conflict",
      side_a: "Government",
      side_b: "Rebels",
      country: "TestCountry",
      latitude: 15.0,
      longitude: 45.0,
      date_start: 3.days.ago,
      type_of_violence: 1,
      best_estimate: 10
    )
  end

  test "GET /api/conflict_events returns JSON array" do
    get "/api/conflict_events"
    assert_response :success

    data = JSON.parse(response.body)
    assert_kind_of Array, data
  end

  test "response contains expected fields" do
    get "/api/conflict_events"
    data = JSON.parse(response.body)
    event = data.find { |e| e["conflict"] == "Test Conflict" }

    assert_not_nil event
    assert_equal "Government", event["side_a"]
    assert_equal "Rebels", event["side_b"]
    assert_in_delta 15.0, event["lat"], 0.01
  end

  test "bounds filtering works" do
    get "/api/conflict_events", params: { lamin: 14.0, lamax: 16.0, lomin: 44.0, lomax: 46.0 }
    data = JSON.parse(response.body)
    assert data.any?

    get "/api/conflict_events", params: { lamin: 0.0, lamax: 5.0, lomin: 0.0, lomax: 5.0 }
    data = JSON.parse(response.body)
    assert_empty data
  end

  test "falls back to conflict pulse zones when no conflict events exist" do
    ConflictEvent.delete_all
    LayerSnapshot.create!(
      snapshot_type: "conflict_pulse",
      scope_key: "global",
      payload: {
        zones: [{
          cell_key: "33.0:44.0",
          lat: 33.0,
          lng: 44.0,
          theater: "Middle East / Iran War",
          situation_name: "Iraq Theater",
          pulse_score: 78,
          top_headlines: ["Regional escalation cluster"],
          detected_at: Time.current.iso8601,
        }],
        strategic_situations: [],
        strike_arcs: [],
        hex_cells: [],
      },
      status: "ready",
      fetched_at: Time.current,
      expires_at: 5.minutes.from_now,
    )

    get "/api/conflict_events"
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal 1, data.length
    assert_equal "Middle East / Iran War", data.first["conflict"]
    assert_equal "Current conflict pulse", data.first["type_label"]
  end

  test "playback-style range requests do not fall back to current conflict pulse" do
    ConflictEvent.delete_all
    LayerSnapshot.create!(
      snapshot_type: "conflict_pulse",
      scope_key: "global",
      payload: {
        zones: [{
          cell_key: "33.0:44.0",
          lat: 33.0,
          lng: 44.0,
          theater: "Middle East / Iran War",
          situation_name: "Iraq Theater",
          pulse_score: 78,
          top_headlines: ["Regional escalation cluster"],
          detected_at: Time.current.iso8601,
        }],
        strategic_situations: [],
        strike_arcs: [],
        hex_cells: [],
      },
      status: "ready",
      fetched_at: Time.current,
      expires_at: 5.minutes.from_now,
    )

    get "/api/conflict_events", params: {
      from: 2.days.ago.iso8601,
      to: 1.day.ago.iso8601,
    }
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal [], data
  end
end
