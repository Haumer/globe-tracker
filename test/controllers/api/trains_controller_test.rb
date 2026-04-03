require "test_helper"

class Api::TrainsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_disabled_layers = LayerAvailability.disabled_layers
  end

  teardown do
    LayerAvailability.disabled_layers = @original_disabled_layers
  end

  test "GET /api/trains returns empty while the layer is disabled" do
    TrainObservation.create!(
      external_id: "oebb-ice-123",
      source: "hafas",
      operator_key: "oebb",
      operator_name: "ÖBB",
      name: "ICE 123",
      category: "ICE",
      category_long: "InterCityExpress",
      flag: "AT",
      latitude: 48.21,
      longitude: 16.37,
      raw_payload: {},
      fetched_at: Time.current,
      expires_at: 90.seconds.from_now,
    )

    get "/api/trains"
    assert_response :success
    assert_equal [], JSON.parse(response.body)
  end

  test "GET /api/trains returns persisted observations when the layer is enabled" do
    TrainObservation.create!(
      external_id: "oebb-ice-123",
      source: "hafas",
      operator_key: "oebb",
      operator_name: "ÖBB",
      name: "ICE 123",
      category: "ICE",
      category_long: "InterCityExpress",
      flag: "AT",
      latitude: 48.21,
      longitude: 16.37,
      direction: "Wien",
      progress: 42,
      snapped_latitude: 48.2099,
      snapped_longitude: 16.3701,
      snap_distance_m: 12.4,
      snap_confidence: "high",
      raw_payload: {},
      fetched_at: Time.current,
      expires_at: 90.seconds.from_now,
    )

    LayerAvailability.disabled_layers = []

    get "/api/trains"
    assert_response :success

    data = JSON.parse(response.body)
    assert_kind_of Array, data
    assert_equal 1, data.size
    assert_equal "ICE 123", data.first["name"]
    assert_equal "ÖBB", data.first["operator"]
    assert_equal 48.2099, data.first["snappedLat"]
    assert_equal "high", data.first["snapConfidence"]
  end

  test "GET /api/trains excludes stale observations and filters by bbox when enabled" do
    TrainObservation.create!(
      external_id: "inside",
      source: "hafas",
      operator_key: "oebb",
      operator_name: "ÖBB",
      name: "RJX 163",
      category: "RJX",
      category_long: "Railjet Xpress",
      flag: "AT",
      latitude: 48.21,
      longitude: 16.37,
      raw_payload: {},
      fetched_at: Time.current,
      expires_at: 90.seconds.from_now,
    )

    TrainObservation.create!(
      external_id: "stale",
      source: "hafas",
      operator_key: "oebb",
      operator_name: "ÖBB",
      name: "OLD 1",
      category: "RE",
      category_long: "Regional",
      flag: "AT",
      latitude: 48.25,
      longitude: 16.4,
      raw_payload: {},
      fetched_at: 10.minutes.ago,
      expires_at: 8.minutes.ago,
    )

    LayerAvailability.disabled_layers = []

    get "/api/trains", params: { bbox: "47.0,15.0,49.0,17.0" }
    assert_response :success

    data = JSON.parse(response.body)
    ids = data.map { |row| row["id"] }
    assert_includes ids, "inside"
    assert_not_includes ids, "stale"
  end
end
