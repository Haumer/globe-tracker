require "test_helper"

class Api::FireHotspotsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hotspot = FireHotspot.create!(
      external_id: "fire-ctrl-001",
      latitude: 44.0,
      longitude: -80.0,
      brightness: 350.0,
      confidence: "high",
      satellite: "Aqua",
      instrument: "MODIS",
      frp: 50.0,
      daynight: "D",
      acq_datetime: 2.hours.ago
    )
  end

  test "GET /api/fire_hotspots returns JSON array" do
    get "/api/fire_hotspots"
    assert_response :success

    data = JSON.parse(response.body)
    assert_kind_of Array, data
  end

  test "response contains array entries with expected structure" do
    get "/api/fire_hotspots"
    data = JSON.parse(response.body)

    assert data.any?
    entry = data.first
    assert_kind_of Array, entry
    assert_equal "fire-ctrl-001", entry[0]
  end
end

class FireHotspotScopingTest < ActionDispatch::IntegrationTest
  def hotspot(id:, lat:, lng:, at:)
    FireHotspot.create!(
      external_id: id, latitude: lat, longitude: lng, brightness: 330.0,
      confidence: "high", satellite: "NOAA-20", instrument: "VIIRS",
      frp: 12.0, daynight: "N", acq_datetime: at
    )
  end

  test "bounds and time range narrow the set; no params keeps the old recent-global contract" do
    inside = hotspot(id: "in", lat: 50.0, lng: 30.0, at: 3.hours.ago)
    hotspot(id: "far", lat: -20.0, lng: 130.0, at: 3.hours.ago)
    hotspot(id: "old", lat: 50.1, lng: 30.1, at: 5.days.ago)

    get "/api/fire_hotspots", params: {
      lamin: 49, lamax: 51, lomin: 29, lomax: 31,
      from: 2.days.ago.iso8601, to: Time.current.iso8601
    }
    assert_response :success
    ids = JSON.parse(response.body).map(&:first)
    assert_equal [inside.external_id], ids

    get "/api/fire_hotspots"
    assert_response :success
    ids = JSON.parse(response.body).map(&:first)
    assert_includes ids, "in"
    assert_includes ids, "far", "paramless requests still serve the recent global set"
    assert_not_includes ids, "old", "recent means the model's 48h default"
  end
end
