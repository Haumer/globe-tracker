require "test_helper"

class RefreshConflictEventsJobTest < ActiveSupport::TestCase
  test "is assigned to the background queue" do
    assert_equal "background", RefreshConflictEventsJob.new.queue_name
  end

  test "tracks polling with source ucdp and poll_type conflict_events" do
    assert_equal "ucdp", RefreshConflictEventsJob.polling_source_resolver
    assert_equal "conflict_events", RefreshConflictEventsJob.polling_type_resolver
  end

  test "calls ConflictEventService.refresh_if_stale" do
    called = false
    ConflictEventService.stub(:refresh_if_stale, -> { called = true; 10 }) do
      RefreshConflictEventsJob.perform_now
    end
    assert called
  end
end
