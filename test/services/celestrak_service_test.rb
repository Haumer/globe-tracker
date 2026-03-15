require "test_helper"

class CelestrakServiceTest < ActiveSupport::TestCase
  test "CATEGORY_GROUPS contains expected categories" do
    assert_instance_of Hash, CelestrakService::CATEGORY_GROUPS
    assert CelestrakService::CATEGORY_GROUPS.key?("starlink")
    assert CelestrakService::CATEGORY_GROUPS.key?("military")
    assert CelestrakService::CATEGORY_GROUPS.key?("analyst")
    assert CelestrakService::CATEGORY_GROUPS.key?("gps-ops")
    assert CelestrakService::CATEGORY_GROUPS.frozen?
  end

  test "BASE_URL points to celestrak" do
    assert_equal "https://celestrak.org/NORAD/elements/gp.php", CelestrakService::BASE_URL
  end

  test "parse_tle extracts satellite data from TLE lines" do
    tle_body = <<~TLE
      ISS (ZARYA)
      1 25544U 98067A   24050.50000000  .00016717  00000-0  10270-3 0  9993
      2 25544  51.6400 200.0000 0005000 100.0000 260.0000 15.50000000400000
    TLE

    result = CelestrakService.send(:parse_tle, tle_body, "stations")
    assert_equal 1, result.size
    assert_equal "ISS (ZARYA)", result[0][:name]
    assert_equal 25544, result[0][:norad_id]
    assert_equal "stations", result[0][:category]
  end

  test "parse_tle names UNKNOWN satellites as CLASSIFIED for analyst category" do
    tle_body = <<~TLE
      UNKNOWN
      1 99999U 00000A   24050.50000000  .00000000  00000-0  00000-0 0  9999
      2 99999  63.0000 200.0000 0005000 100.0000 260.0000 14.00000000400000
    TLE

    result = CelestrakService.send(:parse_tle, tle_body, "analyst")
    assert_equal "CLASSIFIED 99999", result[0][:name]
  end

  test "stale? returns true when no satellites exist" do
    assert CelestrakService.stale?
  end
end
