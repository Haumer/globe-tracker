require "test_helper"

class RssNewsServiceTest < ActiveSupport::TestCase
  setup do
    @service = RssNewsService.new
  end

  test "clean_google_url extracts real URL from Google News redirect" do
    google_url = "https://news.google.com/rss/articles/CBMiRWh0dHBzOi8vd3d3LmJiYy5jb20vbmV3cy93b3JsZC?url=https%3A%2F%2Fwww.bbc.com%2Fnews%2Fworld-12345&foo=bar"
    result = @service.send(:clean_google_url, google_url)
    assert_equal "https://www.bbc.com/news/world-12345", result
  end

  test "clean_google_url returns original URL when no url= param" do
    url = "https://news.google.com/rss/topics/something"
    result = @service.send(:clean_google_url, url)
    assert_equal url, result
  end

  test "parse_pub_date handles Time object from pubDate" do
    item = OpenStruct.new(pubDate: Time.new(2025, 6, 15, 12, 0, 0, "UTC"))
    result = @service.send(:parse_pub_date, item)
    assert_kind_of Time, result
    assert_equal 2025, result.year
  end

  test "parse_pub_date returns nil for item with no date" do
    item = OpenStruct.new
    result = @service.send(:parse_pub_date, item)
    assert_nil result
  end

  test "SOURCES is a non-empty hash" do
    assert_kind_of Hash, RssNewsService::SOURCES
    assert RssNewsService::SOURCES.size > 0
  end

  test "GOOGLE_NEWS_FEEDS is a non-empty hash" do
    assert_kind_of Hash, RssNewsService::GOOGLE_NEWS_FEEDS
    assert RssNewsService::GOOGLE_NEWS_FEEDS.size > 0
  end

  test "stale? returns true when no cache entry" do
    # null_store always returns nil, so stale? is always true in test
    assert RssNewsService.stale?
  end

  test "class responds to refresh_if_stale" do
    assert_respond_to RssNewsService, :refresh_if_stale
  end
end
