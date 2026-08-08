require "test_helper"

class RssNewsServiceTest < ActiveSupport::TestCase
  setup do
    @service = RssNewsService.new
    SourceFeedStatus.delete_all
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

  # Regression: Google News `when:Nd` bounds indexing recency, not the reported
  # pubDate, so `site:` feeds returned static pages (homepages, section indexes,
  # author profiles) carrying their original dates. Production ingested a
  # Brookings landing page dated 2006 and a White House index page dated 2017.
  test "items older than their feed's declared when: window are rejected" do
    now = Time.utc(2026, 8, 8, 10)
    svc = RssNewsService.new
    brookings = "https://news.google.com/rss/search?q=site:brookings.edu+when:7d&hl=en-US"

    assert svc.send(:item_outside_feed_window?, Time.utc(2006, 3, 15), brookings, now: now),
      "a 2006 pubDate must not survive a when:7d feed"
    assert svc.send(:item_outside_feed_window?, Time.utc(2017, 12, 14), brookings, now: now),
      "a 2017 pubDate must not survive a when:7d feed"
    refute svc.send(:item_outside_feed_window?, now - 2.days, brookings, now: now),
      "a genuinely recent article must pass"
  end

  test "when: window is parsed per feed, with slack for timezone drift" do
    svc = RssNewsService.new

    assert_equal 2.days + 1.day, svc.send(:max_item_age_for, "https://news.google.com/rss/search?q=site:x.com+when:2d")
    assert_equal 7.days + 1.day, svc.send(:max_item_age_for, "https://news.google.com/rss/search?q=site:x.com+when:7d")
    assert_equal 12.hours + 1.day, svc.send(:max_item_age_for, "https://news.google.com/rss/search?q=site:x.com+when:12h")
    assert_equal RssNewsService::DEFAULT_MAX_ITEM_AGE, svc.send(:max_item_age_for, "https://example.com/feed.xml")
  end

  test "a boundary-hugging item inside the slack window is kept" do
    now = Time.utc(2026, 8, 8, 10)
    svc = RssNewsService.new
    feed = "https://news.google.com/rss/search?q=site:x.com+when:2d"

    refute svc.send(:item_outside_feed_window?, now - 2.days - 12.hours, feed, now: now),
      "must not trim genuine articles at the window boundary"
  end

  test "missing and future pubDates are handled" do
    now = Time.utc(2026, 8, 8, 10)
    svc = RssNewsService.new
    feed = "https://news.google.com/rss/search?q=site:x.com+when:2d"

    refute svc.send(:item_outside_feed_window?, nil, feed, now: now),
      "a missing date is not evidence of staleness"
    refute svc.send(:item_outside_feed_window?, now + 2.hours, feed, now: now),
      "publishers post slightly ahead; small future drift is fine"
    assert svc.send(:item_outside_feed_window?, now + 30.days, feed, now: now),
      "a date a month in the future is simply wrong"
  end
end
