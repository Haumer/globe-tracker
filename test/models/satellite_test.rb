require "test_helper"

class SatelliteTest < ActiveSupport::TestCase
  test "observation_capable includes earth observation categories" do
    satellite = Satellite.new(category: "planet")

    assert satellite.observation_capable?
  end

  test "observation_capable includes collection mission types" do
    satellite = Satellite.new(category: "military", mission_type: "radar_imaging")

    assert satellite.observation_capable?
  end

  test "observation_capable excludes communications and navigation satellites" do
    assert_not Satellite.new(category: "starlink").observation_capable?
    assert_not Satellite.new(category: "gps-ops", mission_type: "navigation").observation_capable?
    assert_not Satellite.new(category: "military", mission_type: "milcomms").observation_capable?
  end

  test "observation_capable scope filters to observable satellites" do
    observing = Satellite.create!(
      name: "TEST OBSERVER",
      norad_id: 90001,
      tle_line1: "1 90001U 24001A   24001.00000000  .00000000  00000-0  00000-0 0  0000",
      tle_line2: "2 90001  97.0000   0.0000 0001234   0.0000   0.0000 15.00000000000000",
      category: "military",
      mission_type: "imaging",
    )
    ignored = Satellite.create!(
      name: "TEST COMMS",
      norad_id: 90002,
      tle_line1: "1 90002U 24001A   24001.00000000  .00000000  00000-0  00000-0 0  0000",
      tle_line2: "2 90002  55.0000   0.0000 0001234   0.0000   0.0000 02.00000000000000",
      category: "military",
      mission_type: "milcomms",
    )

    results = Satellite.observation_capable

    assert_includes results, observing
    assert_not_includes results, ignored
  end
end
