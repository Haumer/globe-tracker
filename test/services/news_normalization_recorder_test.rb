require "test_helper"

class NewsNormalizationRecorderTest < ActiveSupport::TestCase
  test "creates normalized source and article records for ingested news" do
    ingest = NewsIngest.create!(
      source_feed: "BBC World",
      source_endpoint_url: "https://feeds.bbci.co.uk/news/world/rss.xml",
      raw_url: "https://www.bbc.com/news/articles/c9example?utm_source=rss&utm_medium=feed",
      raw_title: "Example article",
      raw_summary: "A summary from the feed",
      raw_published_at: Time.utc(2026, 3, 24, 12, 0, 0),
      fetched_at: Time.utc(2026, 3, 24, 12, 5, 0),
      payload_format: "rss",
      raw_payload: { title: "Example article" },
      http_status: 200,
      content_hash: "bbc-example-hash"
    )

    mapping = NewsNormalizationRecorder.record_all([
      {
        url: "https://www.bbc.com/news/articles/c9example?utm_source=rss&utm_medium=feed",
        title: "Example article",
        name: "BBC World",
        source: "rss",
        category: "conflict",
        credibility: "tier2/low",
        themes: ["ARMEDCONFLICT"],
        published_at: Time.utc(2026, 3, 24, 12, 0, 0),
        fetched_at: Time.utc(2026, 3, 24, 12, 5, 0),
        news_ingest_id: ingest.id,
      },
    ])

    source = NewsSource.first
    article = NewsArticle.first

    assert_equal 1, NewsSource.count
    assert_equal 1, NewsArticle.count
    assert_equal source.id, mapping["https://www.bbc.com/news/articles/c9example?utm_source=rss&utm_medium=feed"][:news_source_id]
    assert_equal article.id, mapping["https://www.bbc.com/news/articles/c9example?utm_source=rss&utm_medium=feed"][:news_article_id]
    assert_equal "core", mapping["https://www.bbc.com/news/articles/c9example?utm_source=rss&utm_medium=feed"][:content_scope]
    assert_equal "BBC World", source.name
    assert_equal "bbc.com", source.publisher_domain
    assert_equal "https://www.bbc.com/news/articles/c9example", article.canonical_url
    assert_equal ingest.id, article.news_ingest_id
  end

  test "deduplicates canonical article urls across tracking params" do
    ingest = NewsIngest.create!(
      source_feed: "Reuters",
      source_endpoint_url: "https://feeds.reuters.com/reuters/worldNews",
      raw_url: "https://www.reuters.com/world/example-story?utm_source=a",
      raw_title: "Story",
      raw_published_at: Time.utc(2026, 3, 24, 12, 0, 0),
      fetched_at: Time.utc(2026, 3, 24, 12, 5, 0),
      payload_format: "rss",
      raw_payload: { title: "Story" },
      http_status: 200,
      content_hash: "reuters-example-hash"
    )

    items = [
      {
        url: "https://www.reuters.com/world/example-story?utm_source=a",
        title: "Story",
        name: "Reuters",
        source: "rss",
        news_ingest_id: ingest.id,
      },
      {
        url: "https://www.reuters.com/world/example-story?utm_medium=b",
        title: "Story",
        name: "Reuters",
        source: "rss",
        news_ingest_id: ingest.id,
      },
    ]

    mapping = NewsNormalizationRecorder.record_all(items)

    assert_equal 1, NewsSource.count
    assert_equal 1, NewsArticle.count
    assert_equal mapping[items.first[:url]][:news_article_id], mapping[items.last[:url]][:news_article_id]
    assert_equal "wire", NewsSource.first.source_kind
  end
end
