require "test_helper"

class Api::PlaybackControllerTest < ActionDispatch::IntegrationTest
  test "GET /api/playback returns JSON with frames" do
    PositionSnapshot.create!(
      entity_type: "flight", entity_id: "f1",
      latitude: 48.0, longitude: 16.0,
      recorded_at: 30.minutes.ago
    )

    get "/api/playback", params: { from: 1.hour.ago.iso8601, to: Time.current.iso8601, type: "flight" }
    assert_response :success

    data = JSON.parse(response.body)
    assert data.key?("frames")
    assert data.key?("from")
    assert data.key?("to")
    assert_equal "flight", data["entity_type"]
  end

  test "GET /api/playback/range returns time range info" do
    get "/api/playback/range"
    assert_response :success

    data = JSON.parse(response.body)
    assert data.key?("total_snapshots")
    assert data.key?("flights")
    assert data.key?("ships")
    assert data.key?("layers")
  end

  test "playback with empty data returns zero frames" do
    get "/api/playback", params: { from: 1.hour.ago.iso8601, to: Time.current.iso8601, type: "flight" }
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal 0, data["frame_count"]
  end

  test "playback with type=all returns unified frames" do
    PositionSnapshot.create!(entity_type: "flight", entity_id: "f1", latitude: 48.0, longitude: 16.0, recorded_at: 30.minutes.ago)
    PositionSnapshot.create!(entity_type: "ship", entity_id: "s1", latitude: 48.0, longitude: 16.0, recorded_at: 30.minutes.ago)

    get "/api/playback", params: { from: 1.hour.ago.iso8601, to: Time.current.iso8601, type: "all" }
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal "all", data["entity_type"]
  end

  test "anonymous playback response reports the server-clamped range" do
    travel_to Time.utc(2026, 3, 31, 9, 10, 0) do
      PositionSnapshot.create!(
        entity_type: "flight",
        entity_id: "f-old",
        latitude: 48.0,
        longitude: 16.0,
        recorded_at: 2.days.ago
      )
      PositionSnapshot.create!(
        entity_type: "flight",
        entity_id: "f-new",
        latitude: 48.1,
        longitude: 16.1,
        recorded_at: 12.hours.ago
      )

      get "/api/playback", params: {
        from: 3.days.ago.iso8601,
        to: Time.current.iso8601,
        type: "flight"
      }
      assert_response :success

      data = JSON.parse(response.body)
      assert_equal 24.hours.ago.utc.iso8601, data["from"]
      assert_equal Time.current.utc.iso8601, data["to"]
      assert_includes data["frames"].values.flatten.map { |frame| frame["id"] }, "f-new"
      refute_includes data["frames"].values.flatten.map { |frame| frame["id"] }, "f-old"
    end
  end
end
