require "test_helper"

class RefreshRssNewsJobTest < ActiveSupport::TestCase
  test "is assigned to the default queue" do
    assert_equal "default", RefreshRssNewsJob.new.queue_name
  end

  test "tracks polling with source rss and poll_type news" do
    assert_equal "rss", RefreshRssNewsJob.polling_source_resolver
    assert_equal "news", RefreshRssNewsJob.polling_type_resolver
  end

  test "calls RssNewsService.refresh_if_stale" do
    called = false
    RssNewsService.stub(:refresh_if_stale, -> { called = true; 15 }) do
      RefreshRssNewsJob.perform_now
    end
    assert called
  end
end
