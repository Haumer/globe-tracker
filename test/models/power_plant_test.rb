require "test_helper"

class PowerPlantTest < ActiveSupport::TestCase
  setup do
    @plant = PowerPlant.create!(
      gppd_idnr: "TEST-PPL-001",
      name: "Test Nuclear Station",
      country_code: "US",
      country_name: "United States",
      latitude: 41.0,
      longitude: -72.0,
      capacity_mw: 2000.0,
      primary_fuel: "Nuclear",
    )
  end

  test "within_bounds filters by lat/lng" do
    results = PowerPlant.within_bounds(lamin: 40.0, lamax: 42.0, lomin: -73.0, lomax: -71.0)
    assert_includes results, @plant

    results = PowerPlant.within_bounds(lamin: 50.0, lamax: 52.0, lomin: 10.0, lomax: 12.0)
    assert_not_includes results, @plant
  end

  test "by_fuel scope filters by primary fuel type" do
    gas = PowerPlant.create!(
      gppd_idnr: "TEST-PPL-002",
      name: "Test Gas Plant",
      latitude: 42.0, longitude: -73.0,
      capacity_mw: 500.0,
      primary_fuel: "Gas",
    )

    assert_includes PowerPlant.by_fuel("Nuclear"), @plant
    assert_not_includes PowerPlant.by_fuel("Nuclear"), gas
    assert_includes PowerPlant.by_fuel("Gas"), gas
  end

  test "by_fuel with blank returns all" do
    results = PowerPlant.by_fuel(nil)
    assert_includes results, @plant
  end

  test "unique gppd_idnr constraint" do
    assert_raises(ActiveRecord::RecordNotUnique) do
      PowerPlant.create!(
        gppd_idnr: "TEST-PPL-001",
        name: "Duplicate",
        latitude: 0.0, longitude: 0.0,
      )
    end
  end
end
