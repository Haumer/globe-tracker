require "test_helper"

class CameraTest < ActiveSupport::TestCase
  setup do
    @camera = Camera.create!(
      webcam_id: "test-cam-1",
      source: "windy",
      title: "Test Webcam",
      latitude: 48.2,
      longitude: 16.3,
      status: "active",
      camera_type: "live",
      is_live: true,
      fetched_at: Time.current,
      expires_at: 30.days.from_now,
    )
  end

  test "validates webcam_id presence" do
    cam = Camera.new(source: "windy", latitude: 0, longitude: 0)
    assert_not cam.valid?
    assert_includes cam.errors[:webcam_id], "can't be blank"
  end

  test "validates source inclusion" do
    cam = Camera.new(webcam_id: "x", source: "invalid", latitude: 0, longitude: 0)
    assert_not cam.valid?
    assert_includes cam.errors[:source], "is not included in the list"
  end

  test "dedup index prevents duplicate webcam_id + source" do
    assert_raises(ActiveRecord::RecordNotUnique) do
      Camera.create!(
        webcam_id: "test-cam-1",
        source: "windy",
        title: "Dupe",
        latitude: 48.2,
        longitude: 16.3,
      )
    end
  end

  test "same webcam_id with different source is allowed" do
    cam = Camera.create!(
      webcam_id: "test-cam-1",
      source: "youtube",
      title: "Same ID different source",
      latitude: 48.2,
      longitude: 16.3,
    )
    assert cam.persisted?
  end

  test "in_bbox scope filters correctly" do
    Camera.create!(webcam_id: "nyc-1", source: "windy", title: "NYC", latitude: 40.7, longitude: -74.0)
    Camera.create!(webcam_id: "ldn-1", source: "windy", title: "London", latitude: 51.5, longitude: -0.1)

    nyc_results = Camera.in_bbox(north: 41.0, south: 40.0, east: -73.0, west: -75.0)
    assert_equal 1, nyc_results.count
    assert_equal "NYC", nyc_results.first.title
  end

  test "stale? returns true when expired" do
    @camera.update!(expires_at: 1.hour.ago)
    assert @camera.stale?
  end

  test "stale? returns false when not expired" do
    assert_not @camera.stale?
  end

  test "alive scope includes active and expired cameras" do
    expired = Camera.create!(
      webcam_id: "exp-1", source: "windy", title: "Expired",
      latitude: 0, longitude: 0, status: "expired",
    )
    dead = Camera.create!(
      webcam_id: "dead-1", source: "windy", title: "Dead",
      latitude: 0, longitude: 0, status: "dead",
    )

    alive = Camera.alive
    assert_includes alive, @camera
    assert_includes alive, expired
    assert_not_includes alive, dead
  end

  test "STALE_AFTER returns correct durations per source" do
    assert_equal 3.hours, Camera::STALE_AFTER["youtube"]
    assert_equal 30.days, Camera::STALE_AFTER["windy"]
    assert_equal 30.days, Camera::STALE_AFTER["nycdot"]
  end
end
