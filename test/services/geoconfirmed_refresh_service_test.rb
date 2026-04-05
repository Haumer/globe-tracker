require "test_helper"

class GeoconfirmedRefreshServiceTest < ActiveSupport::TestCase
  test "timeline recording uses posted_at when available" do
    gc = GeoconfirmedEvent.create!(
      external_id: "gc-timeline-test",
      map_region: "iran",
      title: "GeoConfirmed timeline test",
      latitude: 35.7,
      longitude: 51.4,
      event_time: 3.days.ago,
      posted_at: 2.days.ago,
      fetched_at: Time.current
    )

    GeoconfirmedRefreshService.send(:record_timeline_events, [gc.external_id])

    timeline = TimelineEvent.find_by(eventable_type: "GeoconfirmedEvent", eventable_id: gc.id)
    assert_not_nil timeline
    assert_equal "geoconfirmed", timeline.event_type
    assert_equal gc.posted_at.to_i, timeline.recorded_at.to_i
  end
end
