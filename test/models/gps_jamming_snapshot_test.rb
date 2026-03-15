require "test_helper"

class GpsJammingSnapshotTest < ActiveSupport::TestCase
  setup do
    @snapshot = GpsJammingSnapshot.create!(
      cell_lat: 50.0,
      cell_lng: 30.0,
      total: 100,
      bad: 25,
      percentage: 25.0,
      level: "moderate",
      recorded_at: 30.minutes.ago,
    )
  end

  test "basic creation with all fields" do
    assert_equal 50.0, @snapshot.cell_lat
    assert_equal 30.0, @snapshot.cell_lng
    assert_equal 25.0, @snapshot.percentage
    assert_equal "moderate", @snapshot.level
  end

  test "recent scope returns snapshots from last hour" do
    old = GpsJammingSnapshot.create!(
      cell_lat: 51.0, cell_lng: 31.0,
      total: 50, bad: 5, percentage: 10.0, level: "low",
      recorded_at: 2.hours.ago,
    )

    assert_includes GpsJammingSnapshot.recent, @snapshot
    assert_not_includes GpsJammingSnapshot.recent, old
  end

  test "in_range scope filters by recorded_at" do
    results = GpsJammingSnapshot.in_range(1.hour.ago, Time.current)
    assert_includes results, @snapshot

    results = GpsJammingSnapshot.in_range(1.week.ago, 1.day.ago)
    assert_not_includes results, @snapshot
  end
end
