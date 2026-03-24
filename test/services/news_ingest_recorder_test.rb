require "test_helper"

class NewsIngestRecorderTest < ActiveSupport::TestCase
  test "records raw ingest rows and returns key to ingest id mapping" do
    mapping = NewsIngestRecorder.record_all([
      {
        item_key: "https://example.com/articles/1",
        source_feed: "rss",
        source_endpoint_url: "https://feeds.example.com/world.xml",
        external_id: "abc-1",
        raw_url: "https://example.com/articles/1",
        raw_title: "Example Article",
        raw_summary: "Summary",
        raw_published_at: "2026-03-24T11:00:00Z",
        fetched_at: Time.utc(2026, 3, 24, 11, 5, 0),
        payload_format: "rss",
        raw_payload: { title: "Example Article", link: "https://example.com/articles/1" },
        http_status: 200,
      },
    ])

    ingest = NewsIngest.first
    assert_equal 1, NewsIngest.count
    assert_equal ingest.id, mapping["https://example.com/articles/1"]
    assert_equal "rss", ingest.source_feed
    assert_equal "https://example.com/articles/1", ingest.raw_url
  end

  test "deduplicates identical raw ingests by content hash" do
    items = [
      {
        item_key: "article-1",
        source_feed: "gdelt",
        source_endpoint_url: "https://api.gdeltproject.org/api/v1/gkg_geojson",
        raw_url: "https://example.com/articles/1",
        raw_title: "Example Article",
        raw_published_at: "2026-03-24T11:00:00Z",
        fetched_at: Time.utc(2026, 3, 24, 11, 5, 0),
        payload_format: "json",
        raw_payload: { title: "Example Article", url: "https://example.com/articles/1" },
        http_status: 200,
      },
      {
        item_key: "article-1-duplicate",
        source_feed: "gdelt",
        source_endpoint_url: "https://api.gdeltproject.org/api/v1/gkg_geojson",
        raw_url: "https://example.com/articles/1",
        raw_title: "Example Article",
        raw_published_at: "2026-03-24T11:00:00Z",
        fetched_at: Time.utc(2026, 3, 24, 11, 6, 0),
        payload_format: "json",
        raw_payload: { title: "Example Article", url: "https://example.com/articles/1" },
        http_status: 200,
      },
    ]

    mapping = NewsIngestRecorder.record_all(items)

    assert_equal 1, NewsIngest.count
    assert_equal mapping["article-1"], mapping["article-1-duplicate"]
  end
end
