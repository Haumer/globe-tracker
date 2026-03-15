require "test_helper"

class SnapshotRecorderTest < ActiveSupport::TestCase
  class FakeRecorder
    extend SnapshotRecorder
    # Make private methods accessible for testing
    public_class_method :snapshot_unchanged?, :heading_delta
  end

  test "thresholds are defined" do
    assert_equal 0.001, SnapshotRecorder::LAT_LNG_THRESHOLD
    assert_equal 50, SnapshotRecorder::ALT_THRESHOLD
    assert_equal 2, SnapshotRecorder::HEADING_THRESHOLD
    assert_equal 5, SnapshotRecorder::SPEED_THRESHOLD
  end

  test "heading_delta handles normal difference" do
    assert_equal 10, FakeRecorder.heading_delta(180, 170)
  end

  test "heading_delta handles wraparound" do
    assert_equal 2, FakeRecorder.heading_delta(359, 1)
    assert_equal 2, FakeRecorder.heading_delta(1, 359)
  end

  test "snapshot_unchanged? returns false when no previous snapshot" do
    assert_not FakeRecorder.snapshot_unchanged?(nil, { latitude: 51.5, longitude: -0.1 })
  end

  test "snapshot_unchanged? returns true when position is same" do
    last = OpenStruct.new(latitude: 51.5, longitude: -0.1, altitude: 10000, heading: 90, speed: 200, recorded_at: Time.current)
    record = { latitude: 51.5, longitude: -0.1, altitude: 10000, heading: 90, speed: 200 }
    assert FakeRecorder.snapshot_unchanged?(last, record)
  end

  test "snapshot_unchanged? returns false when position moved significantly" do
    last = OpenStruct.new(latitude: 51.5, longitude: -0.1, altitude: 10000, heading: 90, speed: 200, recorded_at: Time.current)
    record = { latitude: 52.0, longitude: 0.5, altitude: 10000, heading: 120, speed: 200 }
    assert_not FakeRecorder.snapshot_unchanged?(last, record)
  end

  test "record_flight_snapshots does nothing for blank records" do
    FakeRecorder.record_flight_snapshots(nil)
    FakeRecorder.record_flight_snapshots([])
  end
end
