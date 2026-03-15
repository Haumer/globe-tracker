require "test_helper"

class TimelineEventTest < ActiveSupport::TestCase
  test "creation with polymorphic association" do
    eq = Earthquake.create!(
      external_id: "tl-eq-1", title: "M5.0 test", magnitude: 5.0,
      latitude: 35.0, longitude: -118.0, depth: 10,
      event_time: 1.hour.ago, fetched_at: Time.current
    )
    te = TimelineEvent.create!(
      event_type: "earthquake",
      eventable: eq,
      latitude: 35.0, longitude: -118.0,
      recorded_at: 1.hour.ago
    )
    assert te.persisted?
    assert_equal eq, te.eventable
  end

  test "in_range scope filters by recorded_at" do
    eq = Earthquake.create!(
      external_id: "tl-eq-2", title: "Old quake", magnitude: 4.0,
      latitude: 35.0, longitude: -118.0, depth: 10,
      event_time: 3.hours.ago, fetched_at: Time.current
    )
    eq2 = Earthquake.create!(
      external_id: "tl-eq-3", title: "Recent quake", magnitude: 4.5,
      latitude: 36.0, longitude: -119.0, depth: 15,
      event_time: 30.minutes.ago, fetched_at: Time.current
    )
    TimelineEvent.create!(event_type: "earthquake", eventable: eq, latitude: 35.0, longitude: -118.0, recorded_at: 3.hours.ago)
    TimelineEvent.create!(event_type: "earthquake", eventable: eq2, latitude: 36.0, longitude: -119.0, recorded_at: 30.minutes.ago)

    results = TimelineEvent.in_range(1.hour.ago, Time.current)
    assert_equal 1, results.count
  end

  test "of_type scope filters by event_type" do
    eq = Earthquake.create!(
      external_id: "tl-eq-4", title: "Quake", magnitude: 5.0,
      latitude: 35.0, longitude: -118.0, depth: 10,
      event_time: 1.hour.ago, fetched_at: Time.current
    )
    ne = NaturalEvent.create!(
      external_id: "tl-ne-1", title: "Storm", latitude: 25.0, longitude: -80.0,
      event_date: 1.hour.ago, fetched_at: Time.current
    )
    TimelineEvent.create!(event_type: "earthquake", eventable: eq, latitude: 35.0, longitude: -118.0, recorded_at: 1.hour.ago)
    TimelineEvent.create!(event_type: "natural_event", eventable: ne, latitude: 25.0, longitude: -80.0, recorded_at: 1.hour.ago)

    assert_equal 1, TimelineEvent.of_type("earthquake").count
    assert_equal 1, TimelineEvent.of_type("natural_event").count
  end

  test "within_bounds filters by latitude and longitude" do
    eq = Earthquake.create!(
      external_id: "tl-eq-5", title: "Vienna quake", magnitude: 3.0,
      latitude: 48.2, longitude: 16.3, depth: 5,
      event_time: 1.hour.ago, fetched_at: Time.current
    )
    eq2 = Earthquake.create!(
      external_id: "tl-eq-6", title: "LA quake", magnitude: 3.5,
      latitude: 34.0, longitude: -118.0, depth: 10,
      event_time: 1.hour.ago, fetched_at: Time.current
    )
    TimelineEvent.create!(event_type: "earthquake", eventable: eq, latitude: 48.2, longitude: 16.3, recorded_at: 1.hour.ago)
    TimelineEvent.create!(event_type: "earthquake", eventable: eq2, latitude: 34.0, longitude: -118.0, recorded_at: 1.hour.ago)

    bounds = { lamin: 47.0, lamax: 49.0, lomin: 15.0, lomax: 17.0 }
    results = TimelineEvent.within_bounds(bounds)
    assert_equal 1, results.count
  end
end
