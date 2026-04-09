require "test_helper"

class NewsArticleTest < ActiveSupport::TestCase
  setup do
    @source = NewsSource.create!(canonical_key: "reuters", name: "Reuters", source_kind: "publisher")
    @article = NewsArticle.create!(
      news_source: @source,
      url: "https://example.com/article-1",
      canonical_url: "https://example.com/article-1",
      normalization_status: "normalized",
      content_scope: "core"
    )
  end

  test "valid creation" do
    assert @article.persisted?
  end

  test "url is required" do
    r = NewsArticle.new(news_source: @source, canonical_url: "https://x.com/a", normalization_status: "normalized", content_scope: "core")
    r.url = nil
    assert_not r.valid?
    assert_includes r.errors[:url], "can't be blank"
  end

  test "canonical_url is required" do
    r = NewsArticle.new(news_source: @source, url: "https://x.com/a", normalization_status: "normalized", content_scope: "core")
    r.canonical_url = nil
    assert_not r.valid?
    assert_includes r.errors[:canonical_url], "can't be blank"
  end

  test "belongs_to news_source" do
    assert_equal @source, @article.news_source
  end

  test "news_ingest is optional" do
    assert_nil @article.news_ingest
  end

  test "has_many news_claims" do
    assert_respond_to @article, :news_claims
  end

  test "has_many news_events" do
    assert_respond_to @article, :news_events
  end

  test "hydration_pending scope" do
    pending = NewsArticle.create!(
      news_source: @source, url: "https://x.com/p1", canonical_url: "https://x.com/p1",
      normalization_status: "normalized", content_scope: "core", hydration_status: "queued"
    )
    done = NewsArticle.create!(
      news_source: @source, url: "https://x.com/p2", canonical_url: "https://x.com/p2",
      normalization_status: "normalized", content_scope: "core", hydration_status: "complete"
    )
    results = NewsArticle.hydration_pending
    assert_includes results, pending
    assert_not_includes results, done
  end
end
