require "test_helper"

class Api::PowerPlantsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @plant = PowerPlant.create!(
      gppd_idnr: "PP-CTRL-001",
      name: "Test Nuclear Plant",
      latitude: 48.0,
      longitude: 16.0,
      primary_fuel: "Nuclear",
      capacity_mw: 1200,
      country_code: "AT"
    )
  end

  test "GET /api/power_plants returns JSON array" do
    get "/api/power_plants"
    assert_response :success

    data = JSON.parse(response.body)
    assert_kind_of Array, data
  end

  test "response contains compact array entries" do
    get "/api/power_plants"
    data = JSON.parse(response.body)

    assert data.any?
    entry = data.first
    assert_kind_of Array, entry
    # [id, lat, lng, fuel, capacity, name, country_code]
    assert_equal 7, entry.size
    assert_equal "Nuclear", entry[3]
  end
end
