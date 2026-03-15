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
