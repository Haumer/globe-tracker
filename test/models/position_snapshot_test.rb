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
    now = Time.current
    3.times do |i|
      PositionSnapshot.create!(
        entity_type: "flight", entity_id: "f1",
        latitude: 48.0 + i * 0.1, longitude: 16.0,
        recorded_at: now - (60 * i).seconds
      )
    end

    frames = PositionSnapshot.playback_frames(
      entity_type: "flight", from: now - 5.minutes, to: now, bounds: {}, interval: 30
    )
    assert_kind_of Hash, frames
    assert frames.values.all? { |v| v.is_a?(Array) }
  end

  test "purge_older_than removes old snapshots" do
    PositionSnapshot.create!(entity_type: "flight", entity_id: "old", latitude: 48.0, longitude: 16.0, recorded_at: 48.hours.ago)
    PositionSnapshot.create!(entity_type: "flight", entity_id: "new", latitude: 48.0, longitude: 16.0, recorded_at: 1.hour.ago)

    PositionSnapshot.purge_older_than(24.hours)
    assert_equal 1, PositionSnapshot.count
    assert_equal "new", PositionSnapshot.first.entity_id
  end
end
