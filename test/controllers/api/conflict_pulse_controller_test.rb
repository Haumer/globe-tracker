require "test_helper"

class Api::ConflictPulseControllerTest < ActionDispatch::IntegrationTest
  test "index returns zones array" do
    LayerSnapshot.create!(
      snapshot_type: "conflict_pulse",
      scope_key: "global",
      payload: { zones: [], strategic_situations: [], strike_arcs: [], hex_cells: [] },
      status: "ready",
      fetched_at: Time.current,
      expires_at: 5.minutes.from_now,
    )

    get "/api/conflict_pulse"
    assert_response :success
    data = JSON.parse(response.body)
    assert_kind_of Array, data["zones"]
    assert_kind_of Array, data["strategic_situations"]
    assert_kind_of Integer, data["count"]
    assert_equal "ready", data["snapshot_status"]
  end

  test "index returns pulse zones from persisted snapshot when conflict news exists" do
    6.times do |i|
      NewsEvent.create!(
        url: "https://example.com/pulse-test-#{i}",
        title: "Conflict event #{i}",
        latitude: 33.0, longitude: 44.0,
        tone: -5.0, category: "conflict",
        source: ["reuters", "bbc", "cnn"][i % 3],
        published_at: (i * 2).hours.ago,
        fetched_at: Time.current,
      )
    end

    ConflictPulseSnapshotService.refresh

    get "/api/conflict_pulse"
    assert_response :success
    data = JSON.parse(response.body)
    assert data["count"] > 0
    zone = data["zones"].first
    assert zone["pulse_score"] >= 20
    assert zone["top_headlines"].any?
    assert_kind_of Array, data["strategic_situations"]
    assert_equal "ready", data["snapshot_status"]
  end
end
