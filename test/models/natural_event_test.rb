require "test_helper"

class NaturalEventTest < ActiveSupport::TestCase
  setup do
    @event = NaturalEvent.create!(
      external_id: "EONET-TEST-001",
      title: "Wildfire in California",
      category_id: "wildfires",
      category_title: "Wildfires",
      latitude: 34.0,
      longitude: -118.0,
      event_date: 3.hours.ago,
      fetched_at: Time.current,
    )
  end

  test "within_bounds filters by lat/lng" do
    results = NaturalEvent.within_bounds(lamin: 33.0, lamax: 35.0, lomin: -119.0, lomax: -117.0)
    assert_includes results, @event

    results = NaturalEvent.within_bounds(lamin: 50.0, lamax: 52.0, lomin: 10.0, lomax: 12.0)
    assert_not_includes results, @event
  end

  test "recent scope returns events from last 24 hours by fetched_at" do
    old = NaturalEvent.create!(
      external_id: "EONET-TEST-002",
      title: "Old volcano",
      latitude: 0.0, longitude: 0.0,
      event_date: 3.days.ago,
      fetched_at: 3.days.ago,
    )

    assert_includes NaturalEvent.recent, @event
    assert_not_includes NaturalEvent.recent, old
  end

  test "in_range scope filters by event_date" do
    results = NaturalEvent.in_range(6.hours.ago, Time.current)
    assert_includes results, @event

    results = NaturalEvent.in_range(1.week.ago, 1.day.ago)
    assert_not_includes results, @event
  end

  test "unique external_id constraint" do
    assert_raises(ActiveRecord::RecordNotUnique) do
      NaturalEvent.create!(
        external_id: "EONET-TEST-001",
        title: "Duplicate",
        latitude: 0.0, longitude: 0.0,
        fetched_at: Time.current,
      )
    end
  end
end
