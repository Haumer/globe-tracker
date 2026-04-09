require "test_helper"

class RefreshMultiNewsJobTest < ActiveSupport::TestCase
  test "is assigned to the default queue" do
    assert_equal "default", RefreshMultiNewsJob.new.queue_name
  end

  test "tracks polling with source multi-news and poll_type news" do
    assert_equal "multi-news", RefreshMultiNewsJob.polling_source_resolver
    assert_equal "news", RefreshMultiNewsJob.polling_type_resolver
  end

  test "calls MultiNewsService.refresh_if_stale" do
    called = false
    MultiNewsService.stub(:refresh_if_stale, -> { called = true; 20 }) do
      RefreshMultiNewsJob.perform_now
    end
    assert called
  end
end
