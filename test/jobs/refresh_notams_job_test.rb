require "test_helper"

class RefreshNotamsJobTest < ActiveSupport::TestCase
  test "is assigned to the default queue" do
    assert_equal "default", RefreshNotamsJob.new.queue_name
  end

  test "tracks polling with source notams and poll_type notams" do
    assert_equal "notams", RefreshNotamsJob.polling_source_resolver
    assert_equal "notams", RefreshNotamsJob.polling_type_resolver
  end

  test "calls NotamRefreshService.refresh_if_stale" do
    called = false
    NotamRefreshService.stub(:refresh_if_stale, -> { called = true; 12 }) do
      RefreshNotamsJob.perform_now
    end
    assert called
  end
end
