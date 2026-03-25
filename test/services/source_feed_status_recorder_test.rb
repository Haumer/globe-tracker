require "test_helper"

class SourceFeedStatusRecorderTest < ActiveSupport::TestCase
  setup do
    SourceFeedStatus.delete_all
  end

  test "records feed success status" do
    SourceFeedStatusRecorder.record(
      provider: "rss",
      display_name: "BBC World",
      feed_kind: "rss",
      endpoint_url: "https://feeds.bbci.co.uk/news/world/rss.xml",
      status: "success",
      records_fetched: 10,
      records_stored: 6,
      http_status: 200
    )

    status = SourceFeedStatus.last
    assert_equal "rss", status.provider
    assert_equal "BBC World", status.display_name
    assert_equal "success", status.status
    assert_equal 10, status.last_records_fetched
    assert_equal 6, status.last_records_stored
    assert_equal 200, status.last_http_status
    assert_not_nil status.last_success_at
  end

  test "updates existing feed status row on later error" do
    SourceFeedStatusRecorder.record(
      provider: "multi-news",
      display_name: "gnews",
      feed_kind: "api",
      endpoint_url: "https://gnews.io/api/v4/top-headlines",
      status: "success",
      records_fetched: 8,
      records_stored: 4,
      http_status: 200
    )

    SourceFeedStatusRecorder.record(
      provider: "multi-news",
      display_name: "gnews",
      feed_kind: "api",
      endpoint_url: "https://gnews.io/api/v4/top-headlines",
      status: "error",
      http_status: 429,
      error_message: "HTTP 429"
    )

    assert_equal 1, SourceFeedStatus.count
    status = SourceFeedStatus.last
    assert_equal "error", status.status
    assert_equal 429, status.last_http_status
    assert_equal "HTTP 429", status.last_error_message
    assert_not_nil status.last_error_at
  end
end
