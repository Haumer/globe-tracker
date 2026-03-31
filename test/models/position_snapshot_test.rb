require "test_helper"

class PositionSnapshotTest < ActiveSupport::TestCase
  test "creation with required fields" do
    snap = PositionSnapshot.create!(
      entity_type: "flight",
      entity_id: "abc123",
      latitude: 48.2,
      longitude: 16.3,
      recorded_at: Time.current
    )
    assert snap.persisted?
  end

  test "flights scope returns only flight snapshots" do
    PositionSnapshot.create!(entity_type: "flight", entity_id: "f1", latitude: 48.0, longitude: 16.0, recorded_at: Time.current)
    PositionSnapshot.create!(entity_type: "ship", entity_id: "s1", latitude: 48.0, longitude: 16.0, recorded_at: Time.current)

    assert_equal 1, PositionSnapshot.flights.count
    assert_equal "f1", PositionSnapshot.flights.first.entity_id
  end

  test "ships scope returns only ship snapshots" do
    PositionSnapshot.create!(entity_type: "flight", entity_id: "f1", latitude: 48.0, longitude: 16.0, recorded_at: Time.current)
    PositionSnapshot.create!(entity_type: "ship", entity_id: "s1", latitude: 48.0, longitude: 16.0, recorded_at: Time.current)

    assert_equal 1, PositionSnapshot.ships.count
    assert_equal "s1", PositionSnapshot.ships.first.entity_id
  end

  test "in_range scope filters by recorded_at" do
    PositionSnapshot.create!(entity_type: "flight", entity_id: "f1", latitude: 48.0, longitude: 16.0, recorded_at: 2.hours.ago)
    PositionSnapshot.create!(entity_type: "flight", entity_id: "f2", latitude: 48.0, longitude: 16.0, recorded_at: 30.minutes.ago)

    results = PositionSnapshot.in_range(1.hour.ago, Time.current)
    assert_equal 1, results.count
    assert_equal "f2", results.first.entity_id
  end

  test "playback_frames groups by time interval" do
    t0 = Time.utc(2026, 3, 31, 9, 5, 0)
    PositionSnapshot.create!(entity_type: "flight", entity_id: "f1", latitude: 48.0, longitude: 16.0, recorded_at: t0)
    PositionSnapshot.create!(entity_type: "flight", entity_id: "f1", latitude: 48.1, longitude: 16.0, recorded_at: t0 + 20.minutes)
    PositionSnapshot.create!(entity_type: "flight", entity_id: "f1", latitude: 48.2, longitude: 16.0, recorded_at: t0 + 35.minutes)

    frames = PositionSnapshot.playback_frames(
      entity_type: "flight", from: t0, to: t0 + 1.hour, bounds: {}, interval: 30.minutes.to_i
    )
    assert_kind_of Hash, frames
    assert frames.values.all? { |v| v.is_a?(Array) }
    assert_equal 2, frames.size
    assert_equal 48.1, frames.values.first.first.latitude
    assert_equal 48.2, frames.values.last.first.latitude
  end

  test "purge_older_than removes old snapshots" do
    PositionSnapshot.create!(entity_type: "flight", entity_id: "old", latitude: 48.0, longitude: 16.0, recorded_at: 48.hours.ago)
    PositionSnapshot.create!(entity_type: "flight", entity_id: "new", latitude: 48.0, longitude: 16.0, recorded_at: 1.hour.ago)

    PositionSnapshot.purge_older_than(24.hours)
    assert_equal 1, PositionSnapshot.count
    assert_equal "new", PositionSnapshot.first.entity_id
  end
end
