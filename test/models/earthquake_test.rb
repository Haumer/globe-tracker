require "test_helper"

class EarthquakeTest < ActiveSupport::TestCase
  setup do
    @eq = Earthquake.create!(
      external_id: "us2025eq001",
      title: "10km NE of Testville",
      magnitude: 5.2,
      magnitude_type: "mww",
      latitude: 35.0,
      longitude: -118.0,
      depth: 12.5,
      event_time: 2.hours.ago,
      tsunami: false,
      alert: "green",
      fetched_at: Time.current,
    )
  end

  test "within_bounds filters by lat/lng" do
    # Inside bounds
    results = Earthquake.within_bounds(lamin: 34.0, lamax: 36.0, lomin: -119.0, lomax: -117.0)
    assert_includes results, @eq

    # Outside bounds
    results = Earthquake.within_bounds(lamin: 40.0, lamax: 42.0, lomin: -75.0, lomax: -73.0)
    assert_not_includes results, @eq
  end

  test "within_bounds with nil bounds returns all" do
    results = Earthquake.within_bounds(nil)
    assert_includes results, @eq
  end

  test "recent scope returns recent earthquakes" do
    old = Earthquake.create!(
      external_id: "us2025old",
      title: "Old quake",
      magnitude: 3.0,
      latitude: 0, longitude: 0, depth: 5,
      event_time: 3.days.ago,
      fetched_at: Time.current,
    )

    recent = Earthquake.recent
    assert_includes recent, @eq
    assert_not_includes recent, old
  end

  test "in_range scope filters by time range" do
    results = Earthquake.in_range(6.hours.ago, Time.current)
    assert_includes results, @eq

    results = Earthquake.in_range(1.week.ago, 1.day.ago)
    assert_not_includes results, @eq
  end

  test "unique external_id constraint" do
    assert_raises(ActiveRecord::RecordNotUnique) do
      Earthquake.create!(
        external_id: "us2025eq001",
        title: "Duplicate",
        magnitude: 4.0,
        latitude: 35.0, longitude: -118.0, depth: 10,
        event_time: 1.hour.ago,
        fetched_at: Time.current,
      )
    end
  end
end
