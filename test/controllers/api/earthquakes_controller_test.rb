require "test_helper"

class Api::EarthquakesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @eq1 = Earthquake.create!(
      external_id: "us2025test001",
      title: "10km SW of Springfield",
      magnitude: 4.5,
      magnitude_type: "ml",
      latitude: 37.2,
      longitude: -93.3,
      depth: 8.0,
      event_time: 1.hour.ago,
      fetched_at: Time.current,
    )
    @eq2 = Earthquake.create!(
      external_id: "us2025test002",
      title: "20km NE of Shelbyville",
      magnitude: 2.8,
      magnitude_type: "md",
      latitude: 39.5,
      longitude: -89.7,
      depth: 5.0,
      event_time: 3.hours.ago,
      fetched_at: Time.current,
    )
  end

  test "GET /api/earthquakes returns JSON array" do
    get "/api/earthquakes"
    assert_response :success

    data = JSON.parse(response.body)
    assert_kind_of Array, data
    assert data.length >= 2

    ids = data.map { |e| e["id"] }
    assert_includes ids, "us2025test001"
    assert_includes ids, "us2025test002"
  end

  test "earthquakes are ordered by event_time desc" do
    get "/api/earthquakes"
    data = JSON.parse(response.body)

    times = data.map { |e| e["time"] }.compact
    assert_equal times, times.sort.reverse
  end

  test "earthquake response contains expected fields" do
    get "/api/earthquakes"
    data = JSON.parse(response.body)
    eq = data.find { |e| e["id"] == "us2025test001" }

    assert_equal "10km SW of Springfield", eq["title"]
    assert_equal 4.5, eq["mag"]
    assert_equal "ml", eq["magType"]
    assert_in_delta 37.2, eq["lat"], 0.01
    assert_in_delta -93.3, eq["lng"], 0.01
    assert_not eq["tsunami"]
  end

  test "time range filtering works" do
    old_eq = Earthquake.create!(
      external_id: "us2025old",
      title: "Old quake",
      magnitude: 3.0,
      latitude: 35.0, longitude: -90.0, depth: 5.0,
      event_time: 3.days.ago,
      fetched_at: Time.current,
    )

    # Default (recent 24h) should exclude old
    get "/api/earthquakes"
    data = JSON.parse(response.body)
    ids = data.map { |e| e["id"] }
    assert_not_includes ids, "us2025old"

    # Explicit time range should include old
    get "/api/earthquakes", params: { from: 4.days.ago.iso8601, to: Time.current.iso8601 }
    data = JSON.parse(response.body)
    ids = data.map { |e| e["id"] }
    assert_includes ids, "us2025old"
  end
end
