require "test_helper"

class Api::PlaybackControllerTest < ActionDispatch::IntegrationTest
  test "GET /api/playback returns JSON with frames" do
    PositionSnapshot.create!(
      entity_type: "flight", entity_id: "f1",
      latitude: 48.0, longitude: 16.0,
      recorded_at: 30.minutes.ago
    )

    get "/api/playback", params: {
      from: 1.hour.ago.iso8601,
      to: Time.current.iso8601,
      type: "flight",
      lamin: 47.5, lamax: 48.5, lomin: 15.5, lomax: 16.5
    }
    assert_response :success

    data = JSON.parse(response.body)
    assert data.key?("frames")
    assert data.key?("from")
    assert data.key?("to")
    assert_equal "flight", data["entity_type"]
  end

  test "GET /api/playback preserves raw timestamps for 24 hour replay by default" do
    travel_to Time.utc(2026, 3, 31, 10, 0, 0) do
      t0 = Time.current - 30.minutes
      PositionSnapshot.create!(entity_type: "flight", entity_id: "f1", latitude: 48.0, longitude: 16.0, recorded_at: t0)
      PositionSnapshot.create!(entity_type: "flight", entity_id: "f1", latitude: 48.1, longitude: 16.1, recorded_at: t0 + 5.minutes)
      PositionSnapshot.create!(entity_type: "flight", entity_id: "f1", latitude: 48.2, longitude: 16.2, recorded_at: t0 + 10.minutes)

      get "/api/playback", params: {
        from: 1.hour.ago.iso8601,
        to: Time.current.iso8601,
        type: "flight",
        lamin: 47.5, lamax: 48.5, lomin: 15.5, lomax: 16.5
      }
      assert_response :success

      data = JSON.parse(response.body)
      assert_equal 3, data["frame_count"]
      assert_equal [t0.utc.iso8601, (t0 + 5.minutes).utc.iso8601, (t0 + 10.minutes).utc.iso8601], data["frames"].keys
    end
  end

  test "GET /api/playback/range returns time range info" do
    get "/api/playback/range"
    assert_response :success

    data = JSON.parse(response.body)
    assert data.key?("total_snapshots")
    assert data.key?("flights")
    assert data.key?("ships")
    assert data.key?("layers")
    assert data["layers"].key?("heat_signatures")
    assert data["layers"].key?("geoconfirmed")
  end

  test "playback with empty data returns zero frames" do
    get "/api/playback", params: {
      from: 1.hour.ago.iso8601,
      to: Time.current.iso8601,
      type: "flight",
      lamin: 47.5, lamax: 48.5, lomin: 15.5, lomax: 16.5
    }
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal 0, data["frame_count"]
  end

  test "playback with type=all returns unified frames" do
    PositionSnapshot.create!(entity_type: "flight", entity_id: "f1", latitude: 48.0, longitude: 16.0, recorded_at: 30.minutes.ago)
    PositionSnapshot.create!(entity_type: "ship", entity_id: "s1", latitude: 48.0, longitude: 16.0, recorded_at: 30.minutes.ago)

    get "/api/playback", params: {
      from: 1.hour.ago.iso8601,
      to: Time.current.iso8601,
      type: "all",
      lamin: 47.5, lamax: 48.5, lomin: 15.5, lomax: 16.5
    }
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
        type: "flight",
        lamin: 47.5, lamax: 48.5, lomin: 15.5, lomax: 16.5
      }
      assert_response :success

      data = JSON.parse(response.body)
      assert_equal 24.hours.ago.utc.iso8601, data["from"]
      assert_equal Time.current.utc.iso8601, data["to"]
      assert_includes data["frames"].values.flatten.map { |frame| frame["id"] }, "f-new"
      refute_includes data["frames"].values.flatten.map { |frame| frame["id"] }, "f-old"
    end
  end

  test "playback without bounds returns a safe empty response" do
    PositionSnapshot.create!(
      entity_type: "flight", entity_id: "f1",
      latitude: 48.0, longitude: 16.0,
      recorded_at: 30.minutes.ago
    )

    get "/api/playback", params: { from: 1.hour.ago.iso8601, to: Time.current.iso8601, type: "flight" }
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal 0, data["frame_count"]
    assert_equal "viewport_bounds_required", data["error"]
  end

  test "GET /api/playback/events returns seven-day strike playback for fire and geoconfirmed" do
    travel_to Time.utc(2026, 4, 5, 12, 0, 0) do
      fire = FireHotspot.create!(
        external_id: "timeline-fire-1",
        latitude: 35.7,
        longitude: 51.4,
        brightness: 355.0,
        confidence: "n",
        satellite: "Suomi NPP",
        instrument: "VIIRS",
        frp: 24.0,
        daynight: "N",
        acq_datetime: 3.days.ago,
        fetched_at: Time.current
      )
      TimelineEvent.create!(
        event_type: "fire",
        eventable: fire,
        latitude: fire.latitude,
        longitude: fire.longitude,
        recorded_at: fire.acq_datetime
      )

      gc = GeoconfirmedEvent.create!(
        external_id: "timeline-gc-1",
        map_region: "iran",
        title: "Verified strike report",
        description: "Source(s): https://x.com/example/status/1",
        latitude: 35.71,
        longitude: 51.41,
        event_time: 4.days.ago,
        posted_at: 2.days.ago,
        fetched_at: Time.current
      )
      TimelineEvent.create!(
        event_type: "geoconfirmed",
        eventable: gc,
        latitude: gc.latitude,
        longitude: gc.longitude,
        recorded_at: gc.posted_at
      )

      get "/api/playback/events", params: {
        from: 7.days.ago.iso8601,
        to: Time.current.iso8601,
        types: "fire,geoconfirmed",
        lamin: 35.0, lamax: 36.0, lomin: 51.0, lomax: 52.0
      }
      assert_response :success

      data = JSON.parse(response.body)
      fire_event = data.find { |event| event["type"] == "fire" }
      gc_event = data.find { |event| event["type"] == "geoconfirmed" }

      assert_not_nil fire_event
      assert_not_nil gc_event
      assert_equal "heat_signature", fire_event["detectionKind"]
      assert_equal "verified_strike", gc_event["detectionKind"]
      assert_equal "Verified strike report", gc_event["title"]
    end
  end
end
