require "test_helper"

class RssArticleHydrationServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @original_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
    clear_performed_jobs
    Rails.cache.clear
    travel_to Time.utc(2026, 3, 25, 11, 0, 0)
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
    ActiveJob::Base.queue_adapter = @original_queue_adapter
    Rails.cache.clear
    travel_back
  end

  test "enqueue_candidates queues immediate hydration for thin rss articles" do
    article = create_rss_article(
      title: "Delegations regroup",
      summary: nil,
      content_scope: "adjacent"
    )

    assert_enqueued_with(job: RssArticleHydrationJob, args: [article.id]) do
      queued = RssArticleHydrationService.enqueue_candidates([
        {
          news_article_id: article.id,
          content_scope: article.content_scope,
          category: "diplomacy",
          threat_level: "medium",
        },
      ])

      assert_equal 1, queued
    end

    assert_equal "queued", article.reload.hydration_status
    assert_equal "missing_summary", article.hydration_error
  end

  test "enqueue_candidates skips out of scope articles" do
    article = create_rss_article(
      title: "Best pasta recipes for a quick dinner",
      summary: nil,
      content_scope: "out_of_scope"
    )

    assert_no_enqueued_jobs do
      queued = RssArticleHydrationService.enqueue_candidates([
        {
          news_article_id: article.id,
          content_scope: article.content_scope,
          category: "other",
        },
      ])

      assert_equal 0, queued
    end

    assert_equal "not_requested", article.reload.hydration_status
  end

  test "hydrate updates article fields and reruns claim extraction" do
    article = create_rss_article(
      title: "Delegations regroup",
      summary: nil,
      content_scope: "adjacent",
      published_at: Time.utc(2026, 3, 24, 12, 0, 0)
    )

    stub_request(:get, article.url)
      .to_return(
        status: 200,
        headers: { "Content-Type" => "text/html" },
        body: <<~HTML
          <html lang="en">
            <head>
              <link rel="canonical" href="https://example.com/articles/diplomacy-001" />
              <meta property="og:title" content="Delegations regroup in Muscat" />
              <meta property="og:description" content="Iran and the United States will meet next week in Muscat for talks." />
              <meta property="article:published_time" content="2026-03-24T12:10:00Z" />
            </head>
            <body>
              <article><p>Iran and the United States will meet next week in Muscat for talks.</p></article>
            </body>
          </html>
        HTML
      )

    hydrated = RssArticleHydrationService.hydrate(article.id)
    claim = NewsClaim.find_by!(news_article_id: article.id)
    cluster_key = NewsStoryClusterer.recluster_article(article)

    assert hydrated
    assert_equal "hydrated", article.reload.hydration_status
    assert_equal "en", article.language
    assert_equal "Iran and the United States will meet next week in Muscat for talks.", article.summary
    assert_equal "https://example.com/articles/diplomacy-001", article.canonical_url
    assert_equal "diplomacy", claim.event_family
    assert_equal "negotiation", claim.event_type
    assert_not_nil cluster_key
    assert cluster_key.present?
  end

  test "hydrate retries transient failures with backoff" do
    article = create_rss_article(
      title: "Delegations regroup",
      summary: nil,
      content_scope: "adjacent"
    )

    stub_request(:get, article.url).to_timeout

    assert_enqueued_with(job: RssArticleHydrationJob, args: [article.id]) do
      hydrated = RssArticleHydrationService.hydrate(article.id)
      assert_equal false, hydrated
    end

    article.reload
    assert_equal 1, article.hydration_attempts
    assert_equal "queued", article.hydration_status
    assert_equal "open_timeout", article.hydration_error
  end

  test "hydrate forced non-rss article persists maritime signal and clears force reason" do
    source = NewsSource.create!(
      canonical_key: "wire:forced-area",
      name: "Forced Area Source",
      source_kind: "wire",
      publisher_domain: "example.com"
    )
    article = NewsArticle.create!(
      news_source: source,
      url: "https://example.com/hormuz-selective",
      canonical_url: "https://example.com/hormuz-selective",
      title: "Hormuz shipping update",
      summary: nil,
      publisher_name: "Forced Area Source",
      publisher_domain: "example.com",
      content_scope: "core",
      published_at: Time.utc(2026, 3, 25, 10, 0, 0),
      fetched_at: Time.utc(2026, 3, 25, 10, 1, 0),
      metadata: {
        "transport_source" => "api",
        "force_hydration_reason" => "area_candidate:maritime",
        "force_hydration_requested_at" => Time.current.iso8601,
      }
    )

    stub_request(:get, article.url)
      .to_return(
        status: 200,
        headers: { "Content-Type" => "text/html" },
        body: <<~HTML
          <html lang="en">
            <head>
              <meta property="og:title" content="Iran monetizes selective passage in Hormuz" />
              <meta property="og:description" content="Officials described transit fees and permission-based passage for some vessels in the Strait of Hormuz." />
            </head>
            <body>
              <article><p>Officials described transit fees and permission-based passage for some vessels in the Strait of Hormuz.</p></article>
            </body>
          </html>
        HTML
      )

    hydrated = RssArticleHydrationService.hydrate(article.id)

    assert hydrated
    article.reload
    assert_equal "hydrated", article.hydration_status
    assert_nil article.metadata["force_hydration_reason"]
    assert_nil article.metadata["force_hydration_requested_at"]
    assert_equal "restricted_selective", article.metadata.dig("maritime_passage_signal", "state")
    assert_includes article.metadata.dig("maritime_passage_signal", "signals"), "transit_fee"
  end

  private

  def create_rss_article(title:, summary:, content_scope:, published_at: Time.utc(2026, 3, 24, 12, 0, 0))
    source = NewsSource.create!(
      canonical_key: "publisher:example.com",
      name: "Example",
      source_kind: "publisher",
      publisher_domain: "example.com"
    )

    NewsArticle.create!(
      news_source: source,
      url: "https://example.com/rss-story-#{SecureRandom.hex(4)}",
      canonical_url: "https://example.com/rss-story-#{SecureRandom.hex(4)}",
      title: title,
      summary: summary,
      publisher_name: "Example",
      publisher_domain: "example.com",
      language: nil,
      content_scope: content_scope,
      published_at: published_at,
      fetched_at: published_at + 1.minute,
      metadata: { "transport_source" => "rss" }
    )
  end
end
