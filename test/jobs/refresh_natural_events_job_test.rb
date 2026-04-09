require "test_helper"

class RefreshNaturalEventsJobTest < ActiveSupport::TestCase
  test "is assigned to the default queue" do
    assert_equal "default", RefreshNaturalEventsJob.new.queue_name
  end

  test "tracks polling with source natural-events and poll_type natural_events" do
    assert_equal "natural-events", RefreshNaturalEventsJob.polling_source_resolver
    assert_equal "natural_events", RefreshNaturalEventsJob.polling_type_resolver
  end

  test "calls NaturalEventRefreshService.refresh_if_stale" do
    called = false
    NaturalEventRefreshService.stub(:refresh_if_stale, -> { called = true; 6 }) do
      RefreshNaturalEventsJob.perform_now
    end
    assert called
  end
end
