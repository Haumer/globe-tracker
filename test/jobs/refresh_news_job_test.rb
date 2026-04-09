require "test_helper"

class RefreshNewsJobTest < ActiveSupport::TestCase
  test "is assigned to the default queue" do
    assert_equal "default", RefreshNewsJob.new.queue_name
  end

  test "tracks polling with source gdelt and poll_type news" do
    assert_equal "gdelt", RefreshNewsJob.polling_source_resolver
    assert_equal "news", RefreshNewsJob.polling_type_resolver
  end

  test "calls NewsRefreshService.refresh_if_stale" do
    called = false
    NewsRefreshService.stub(:refresh_if_stale, -> { called = true; 30 }) do
      RefreshNewsJob.perform_now
    end
    assert called
  end
end
