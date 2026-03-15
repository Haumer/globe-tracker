require "test_helper"

class Api::SatellitesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @sat = Satellite.create!(
      name: "ISS (ZARYA)",
      norad_id: 25544,
      tle_line1: "1 25544U 98067A   24001.00000000  .00000000  00000-0  00000-0 0  0000",
      tle_line2: "2 25544  51.6400   0.0000 0001234   0.0000   0.0000 15.50000000000000",
      category: "stations",
    )
  end

  test "GET /api/satellites returns JSON array" do
    get "/api/satellites"
    assert_response :success

    data = JSON.parse(response.body)
    assert_kind_of Array, data
  end

  test "satellites response contains expected fields" do
    get "/api/satellites"
    data = JSON.parse(response.body)
    sat = data.find { |s| s["norad_id"] == 25544 }

    assert_not_nil sat
    assert_equal "ISS (ZARYA)", sat["name"]
    assert_equal "stations", sat["category"]
  end

  test "category filter works" do
    Satellite.create!(
      name: "GPS BIIR-2",
      norad_id: 24876,
      tle_line1: "1 24876U 97035A   24001.00000000  .00000000  00000-0  00000-0 0  0000",
      tle_line2: "2 24876  55.0000   0.0000 0100000   0.0000   0.0000 02.00000000000000",
      category: "gps-ops",
    )

    get "/api/satellites", params: { category: "stations" }
    data = JSON.parse(response.body)
    categories = data.map { |s| s["category"] }.uniq
    assert_equal ["stations"], categories
  end
end
