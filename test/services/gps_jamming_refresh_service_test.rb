require "test_helper"

class GpsJammingRefreshServiceTest < ActiveSupport::TestCase
  test "refresh_if_stale returns 0 when data is fresh" do
    GpsJammingSnapshot.create!(
      cell_lat: 48.0, cell_lng: 16.0,
      total: 10, bad: 3,
      percentage: 30.0, level: "high",
      recorded_at: 1.minute.ago,
    )

    result = GpsJammingRefreshService.refresh_if_stale

    assert_equal 0, result
  end

  test "refresh_if_stale runs compute when data is stale" do
    GpsJammingSnapshot.create!(
      cell_lat: 48.0, cell_lng: 16.0,
      total: 10, bad: 3,
      percentage: 30.0, level: "high",
      recorded_at: 10.minutes.ago,
    )

    # No flights means 0 cells produced
    result = GpsJammingRefreshService.refresh_if_stale

    assert_equal 0, result
  end

  test "refresh_if_stale runs compute when no snapshots exist" do
    result = GpsJammingRefreshService.refresh_if_stale

    assert_equal 0, result
  end

  test "compute_snapshot creates jamming cells from flights with low nac_p" do
    # Create enough flights in a cluster to pass the >= 8 threshold
    10.times do |i|
      Flight.create!(
        icao24: "jam#{format('%03d', i)}",
        latitude: 48.0,
        longitude: 16.0,
        nac_p: 2, # low nac_p = bad
        source: "adsb",
        updated_at: 30.minutes.ago,
      )
    end

    result = GpsJammingRefreshService.send(:compute_snapshot)

    assert result >= 1
    assert GpsJammingSnapshot.where("recorded_at > ?", 1.minute.ago).exists?
  end

  test "compute_snapshot ignores flights without nac_p" do
    5.times do |i|
      Flight.create!(
        icao24: "nonac#{format('%03d', i)}",
        latitude: 48.0,
        longitude: 16.0,
        nac_p: nil,
        source: "adsb",
        updated_at: 30.minutes.ago,
      )
    end

    result = GpsJammingRefreshService.send(:compute_snapshot)

    assert_equal 0, result
  end

  test "NACP_THRESHOLD constant is defined" do
    assert_equal 4, GpsJammingRefreshService::NACP_THRESHOLD
  end

  test "STALE_AFTER constant is 5 minutes" do
    assert_equal 5.minutes, GpsJammingRefreshService::STALE_AFTER
  end
end
