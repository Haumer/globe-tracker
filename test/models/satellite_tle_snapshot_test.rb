require "test_helper"

class SatelliteTleSnapshotTest < ActiveSupport::TestCase
  setup do
    @now = Time.current
    @snap = SatelliteTleSnapshot.create!(
      norad_id: 25544,
      name: "ISS (ZARYA)",
      tle_line1: "1 25544U 98067A   21264.51782528  .00000000  00000-0  00000-0 0  9993",
      tle_line2: "2 25544  51.6416 247.4627 0006703 130.5360 325.0288 15.48919999000000",
      category: "stations",
      recorded_at: @now
    )
  end

  test "for_time scope returns snapshots before given time" do
    future = SatelliteTleSnapshot.create!(
      norad_id: 25544,
      name: "ISS (ZARYA)",
      tle_line1: "1 25544U 98067A   21265.51782528  .00000000  00000-0  00000-0 0  9994",
      tle_line2: "2 25544  51.6416 247.4627 0006703 130.5360 325.0288 15.48919999000001",
      category: "stations",
      recorded_at: @now + 1.day
    )

    results = SatelliteTleSnapshot.for_time(@now + 1.second)
    assert_includes results, @snap
    assert_not_includes results, future
  end

  test "purge_older_than removes old snapshots" do
    old = SatelliteTleSnapshot.create!(
      norad_id: 99999,
      name: "OLD SAT",
      tle_line1: "1 99999U 00000A   21200.00000000  .00000000  00000-0  00000-0 0  0000",
      tle_line2: "2 99999  00.0000 000.0000 0000000 000.0000 000.0000 00.00000000000000",
      recorded_at: 10.days.ago
    )

    SatelliteTleSnapshot.purge_older_than(7.days)
    assert_not SatelliteTleSnapshot.exists?(old.id)
    assert SatelliteTleSnapshot.exists?(@snap.id)
  end

  test "required columns enforce NOT NULL at database level" do
    assert_raises(ActiveRecord::NotNullViolation) do
      SatelliteTleSnapshot.connection.execute(
        "INSERT INTO satellite_tle_snapshots (norad_id, tle_line1, tle_line2, recorded_at) VALUES (NULL, NULL, NULL, NULL)"
      )
    end
  end
end
