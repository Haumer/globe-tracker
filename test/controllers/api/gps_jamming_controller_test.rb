require "test_helper"

class Api::GpsJammingControllerTest < ActionDispatch::IntegrationTest
  test "GET /api/gps_jamming returns JSON array" do
    get "/api/gps_jamming"
    assert_response :success

    data = JSON.parse(response.body)
    assert_kind_of Array, data
  end

  test "returns jamming snapshots with expected fields" do
    GpsJammingSnapshot.create!(
      cell_lat: 50.0, cell_lng: 35.0, total: 100, bad: 15,
      percentage: 15.0, level: "high", recorded_at: 10.minutes.ago
    )

    get "/api/gps_jamming"
    data = JSON.parse(response.body)

    assert data.any?
    snap = data.first
    assert snap.key?("lat")
    assert snap.key?("lng")
    assert snap.key?("pct")
    assert snap.key?("level")
  end

  test "timeline mode with from/to params" do
    now = Time.current
    GpsJammingSnapshot.create!(
      cell_lat: 50.0, cell_lng: 35.0, total: 50, bad: 10,
      percentage: 20.0, level: "high", recorded_at: now - 30.minutes
    )

    get "/api/gps_jamming", params: { from: (now - 1.hour).iso8601, to: now.iso8601 }
    assert_response :success

    data = JSON.parse(response.body)
    assert_kind_of Array, data
  end
end
