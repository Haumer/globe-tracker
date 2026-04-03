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
    assert_equal "BBC", source.name
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

  test "keeps publisher identity and extracts origin wire for syndicated article" do
    ingest = NewsIngest.create!(
      source_feed: "Jerusalem Post",
      source_endpoint_url: "https://www.jpost.com/rss",
      raw_url: "https://www.jpost.com/middle-east/article-123",
      raw_title: "By Reuters: Israel says talks continue",
      raw_summary: "By Reuters. Diplomats met in Oman.",
      raw_published_at: Time.utc(2026, 3, 25, 8, 0, 0),
      fetched_at: Time.utc(2026, 3, 25, 8, 5, 0),
      payload_format: "rss",
      raw_payload: { "source_name" => "BY REUTERS", "author" => "Reuters" },
      http_status: 200,
      content_hash: "jpost-reuters-hash"
    )

    NewsNormalizationRecorder.record_all([
      {
        url: "https://www.jpost.com/middle-east/article-123",
        title: "By Reuters: Israel says talks continue",
        name: "BY REUTERS",
        source: "rss",
        published_at: Time.utc(2026, 3, 25, 8, 0, 0),
        fetched_at: Time.utc(2026, 3, 25, 8, 5, 0),
        news_ingest_id: ingest.id,
      },
    ])

    source = NewsSource.first
    article = NewsArticle.first

    assert_equal "publisher", source.source_kind
    assert_equal "jpost.com", source.publisher_domain
    assert_equal "Jerusalem Post", source.name
    assert_equal "Reuters", article.origin_source_name
    assert_equal "wire", article.origin_source_kind
    assert_equal "reuters.com", article.origin_source_domain
  end

  test "resolves google news proxy items to the actual outlet" do
    ingest = NewsIngest.create!(
      source_feed: "GN: World",
      source_endpoint_url: "https://news.google.com/rss/topics/example",
      raw_url: "https://news.google.com/rss/articles/abc123",
      raw_title: "Three Iranian women soccer players to return home after seeking asylum in Australia - Reuters",
      raw_summary: "Google News proxy result.",
      raw_published_at: Time.utc(2026, 3, 25, 10, 0, 0),
      fetched_at: Time.utc(2026, 3, 25, 10, 2, 0),
      payload_format: "rss",
      raw_payload: { "source_name" => "GN: World" },
      http_status: 200,
      content_hash: "google-proxy-reuters"
    )

    NewsNormalizationRecorder.record_all([
      {
        url: "https://news.google.com/rss/articles/abc123",
        title: "Three Iranian women soccer players to return home after seeking asylum in Australia - Reuters",
        name: "GN: World",
        source: "rss",
        published_at: Time.utc(2026, 3, 25, 10, 0, 0),
        fetched_at: Time.utc(2026, 3, 25, 10, 2, 0),
        news_ingest_id: ingest.id,
      },
    ])

    source = NewsSource.first
    article = NewsArticle.first

    assert_equal "Reuters", source.name
    assert_equal "wire", source.source_kind
    assert_equal "reuters.com", source.publisher_domain
    assert_equal "Reuters", article.publisher_name
    assert_equal "reuters.com", article.publisher_domain
    assert_nil article.origin_source_name
  end

  test "uses canonical domain names for generic host labels" do
    ingest = NewsIngest.create!(
      source_feed: "worldnews",
      source_endpoint_url: "https://api.worldnewsapi.com/search-news",
      raw_url: "https://www.news.com.au/national/politics/story-example",
      raw_title: "Example politics story",
      raw_summary: "Story summary",
      raw_published_at: Time.utc(2026, 3, 25, 9, 0, 0),
      fetched_at: Time.utc(2026, 3, 25, 9, 1, 0),
      payload_format: "json",
      raw_payload: { "source_country" => "au" },
      http_status: 200,
      content_hash: "news-com-au-example"
    )

    NewsNormalizationRecorder.record_all([
      {
        url: "https://www.news.com.au/national/politics/story-example",
        title: "Example politics story",
        name: "au",
        source: "worldnews",
        published_at: Time.utc(2026, 3, 25, 9, 0, 0),
        fetched_at: Time.utc(2026, 3, 25, 9, 1, 0),
        news_ingest_id: ingest.id,
      },
    ])

    source = NewsSource.first
    article = NewsArticle.first

    assert_equal "News.com.au", source.name
    assert_equal "news.com.au", source.publisher_domain
    assert_equal "News.com.au", article.publisher_name
  end

  test "uses google proxy record name when ingest context is missing" do
    mapping = NewsNormalizationRecorder.record_all([
      {
        url: "https://news.google.com/rss/articles/iran-intl-example",
        title: "Desertions, shortages and army-IRGC rift strain Iran's military - ایران اینترنشنال",
        name: "GN: Iran Intl",
        source: "rss",
        published_at: Time.utc(2026, 3, 25, 11, 0, 0),
        fetched_at: Time.utc(2026, 3, 25, 11, 5, 0),
      },
    ])

    source = NewsSource.first
    article = NewsArticle.first

    assert mapping["https://news.google.com/rss/articles/iran-intl-example"]
    assert_equal "Iran International", source.name
    assert_equal "iranintl.com", source.publisher_domain
    assert_equal "Iran International", article.publisher_name
    assert_equal "iranintl.com", article.publisher_domain
  end

  test "canonicalizes apnews domain as associated press" do
    ingest = NewsIngest.create!(
      source_feed: "AP News",
      source_endpoint_url: "https://news.google.com/rss/search?q=site:apnews.com+when:1d",
      raw_url: "https://apnews.com/article/example",
      raw_title: "Example AP article",
      raw_summary: "Story summary",
      raw_published_at: Time.utc(2026, 3, 25, 12, 0, 0),
      fetched_at: Time.utc(2026, 3, 25, 12, 5, 0),
      payload_format: "rss",
      raw_payload: { "source_name" => "Apnews" },
      http_status: 200,
      content_hash: "apnews-example"
    )

    NewsNormalizationRecorder.record_all([
      {
        url: "https://apnews.com/article/example",
        title: "Example AP article",
        name: "Apnews",
        source: "rss",
        published_at: Time.utc(2026, 3, 25, 12, 0, 0),
        fetched_at: Time.utc(2026, 3, 25, 12, 5, 0),
        news_ingest_id: ingest.id,
      },
    ])

    source = NewsSource.first

    assert_equal "Associated Press", source.name
    assert_equal "wire", source.source_kind
    assert_equal "apnews.com", source.publisher_domain
  end

  test "does not confuse kelownacapnews with apnews" do
    NewsNormalizationRecorder.record_all([
      {
        url: "https://kelownacapnews.com/2026/03/13/story-example",
        title: "White Salmon River, Washington, United States",
        name: "White Salmon River, Washington, United States",
        source: "gdelt",
        published_at: Time.utc(2026, 3, 25, 12, 30, 0),
        fetched_at: Time.utc(2026, 3, 25, 12, 35, 0),
      },
    ])

    source = NewsSource.first
    article = NewsArticle.first

    assert_equal "Kelownacapnews", source.name
    assert_equal "publisher", source.source_kind
    assert_equal "kelownacapnews.com", source.publisher_domain
    assert_equal "Kelownacapnews", article.publisher_name
    assert_equal "kelownacapnews.com", article.publisher_domain
  end

  test "handles non-hash ingest payloads without warning-level failure" do
    ingest = NewsIngest.create!(
      source_feed: "worldnews",
      source_endpoint_url: "https://api.worldnewsapi.com/search-news",
      raw_url: "https://example.com/shipping/story",
      raw_title: "Port disruption raises freight costs",
      raw_summary: "Story summary",
      raw_published_at: Time.utc(2026, 4, 3, 12, 0, 0),
      fetched_at: Time.utc(2026, 4, 3, 12, 5, 0),
      payload_format: "json",
      raw_payload: "unexpected string payload",
      http_status: 200,
      content_hash: "string-payload-example"
    )

    mapping = NewsNormalizationRecorder.record_all([
      {
        url: "https://example.com/shipping/story",
        title: "Port disruption raises freight costs",
        name: "Example Maritime Journal",
        source: "worldnews",
        published_at: Time.utc(2026, 4, 3, 12, 0, 0),
        fetched_at: Time.utc(2026, 4, 3, 12, 5, 0),
        news_ingest_id: ingest.id,
      },
    ])

    article = NewsArticle.first
    source = NewsSource.first

    assert mapping["https://example.com/shipping/story"]
    assert_equal "publisher", source.source_kind
    assert_equal "example.com", source.publisher_domain
    assert_equal "Example", article.publisher_name
  end
end
