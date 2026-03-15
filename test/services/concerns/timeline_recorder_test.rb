require "test_helper"

class TimelineRecorderTest < ActiveSupport::TestCase
  class FakeTimelineService
    include TimelineRecorder
    public :record_timeline_events
  end

  test "record_timeline_events does nothing for blank unique_values" do
    svc = FakeTimelineService.new
    svc.record_timeline_events(
      event_type: "test",
      model_class: Earthquake,
      unique_key: :external_id,
      unique_values: [],
      time_column: :event_time
    )
  end

  test "record_timeline_events does nothing for nil unique_values" do
    svc = FakeTimelineService.new
    svc.record_timeline_events(
      event_type: "test",
      model_class: Earthquake,
      unique_key: :external_id,
      unique_values: nil,
      time_column: :event_time
    )
  end

  test "record_timeline_events queries model and upserts" do
    eq = Earthquake.create!(
      external_id: "tl-test-1",
      title: "Test quake",
      magnitude: 5.0,
      latitude: 35.0,
      longitude: 139.0,
      event_time: 1.hour.ago
    )

    svc = FakeTimelineService.new
    svc.record_timeline_events(
      event_type: "earthquake",
      model_class: Earthquake,
      unique_key: :external_id,
      unique_values: ["tl-test-1"],
      time_column: :event_time
    )

    tl = TimelineEvent.find_by(eventable_type: "Earthquake", eventable_id: eq.id)
    assert_not_nil tl
    assert_equal "earthquake", tl.event_type
  end
end
