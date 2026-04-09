require "test_helper"

class RefreshAcledJobTest < ActiveSupport::TestCase
  test "is assigned to the background queue" do
    assert_equal "background", RefreshAcledJob.new.queue_name
  end

  test "tracks polling with source acled and poll_type conflict_events" do
    assert_equal "acled", RefreshAcledJob.polling_source_resolver
    assert_equal "conflict_events", RefreshAcledJob.polling_type_resolver
  end

  test "calls AcledService.refresh_if_stale" do
    called = false
    AcledService.stub(:refresh_if_stale, -> { called = true; 42 }) do
      RefreshAcledJob.perform_now
    end
    assert called
  end
end
