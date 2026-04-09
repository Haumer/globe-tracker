require "test_helper"

class GeoconfirmedEventTest < ActiveSupport::TestCase
  setup do
    @event = GeoconfirmedEvent.create!(
      external_id: "geo-001",
      map_region: "ukraine",
      latitude: 48.5,
      longitude: 35.0,
      fetched_at: Time.current,
      event_time: 1.day.ago
    )
  end

  test "valid creation" do
    assert @event.persisted?
  end

  test "external_id is required" do
    r = GeoconfirmedEvent.new(map_region: "ukraine", latitude: 48.5, longitude: 35.0, fetched_at: Time.current)
    assert_not r.valid?
    assert_includes r.errors[:external_id], "can't be blank"
  end

  test "map_region is required" do
    r = GeoconfirmedEvent.new(external_id: "x", latitude: 48.5, longitude: 35.0, fetched_at: Time.current)
    assert_not r.valid?
    assert_includes r.errors[:map_region], "can't be blank"
  end

  test "latitude is required" do
    r = GeoconfirmedEvent.new(external_id: "x", map_region: "ukraine", longitude: 35.0, fetched_at: Time.current)
    assert_not r.valid?
    assert_includes r.errors[:latitude], "can't be blank"
  end

  test "fetched_at is required" do
    r = GeoconfirmedEvent.new(external_id: "x", map_region: "ukraine", latitude: 48.5, longitude: 35.0)
    assert_not r.valid?
    assert_includes r.errors[:fetched_at], "can't be blank"
  end

  test "recent scope returns events from last 30 days" do
    old = GeoconfirmedEvent.create!(
      external_id: "geo-old", map_region: "ukraine",
      latitude: 48.5, longitude: 35.0, fetched_at: Time.current,
      event_time: 60.days.ago
    )
    results = GeoconfirmedEvent.recent
    assert_includes results, @event
    assert_not_includes results, old
  end

  test "for_region scope filters by map_region" do
    other = GeoconfirmedEvent.create!(
      external_id: "geo-other", map_region: "syria",
      latitude: 34.0, longitude: 38.0, fetched_at: Time.current
    )
    results = GeoconfirmedEvent.for_region("ukraine")
    assert_includes results, @event
    assert_not_includes results, other
  end

  test "within_bounds filters by lat/lng" do
    results = GeoconfirmedEvent.within_bounds(lamin: 48.0, lamax: 49.0, lomin: 34.0, lomax: 36.0)
    assert_includes results, @event
  end

  test "timeline_recorded_at prefers posted_at" do
    @event.posted_at = 2.days.ago
    assert_equal @event.posted_at, @event.timeline_recorded_at
  end

  test "timeline_recorded_at falls back to event_time" do
    @event.posted_at = nil
    assert_equal @event.event_time, @event.timeline_recorded_at
  end

  test "timeline_recorded_at falls back to fetched_at" do
    @event.posted_at = nil
    @event.event_time = nil
    assert_equal @event.fetched_at, @event.timeline_recorded_at
  end

  test "has_many timeline_events" do
    assert_respond_to @event, :timeline_events
  end
end
