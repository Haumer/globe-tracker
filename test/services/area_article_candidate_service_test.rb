require "test_helper"

class AreaArticleCandidateServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @original_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
    clear_performed_jobs
    travel_to Time.utc(2026, 3, 30, 12, 0, 0)

    @user = User.create!(email: "area-candidates@example.com", password: "password123")
    @area = @user.area_workspaces.create!(
      name: "Strait of Hormuz",
      scope_type: "preset_region",
      profile: "maritime",
      bounds: { lamin: 24.0, lamax: 28.0, lomin: 54.0, lomax: 58.5 },
      scope_metadata: { region_key: "strait-of-hormuz", region_name: "Strait of Hormuz" },
      default_layers: ["ships", "chokepoints", "news"]
    )
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
    ActiveJob::Base.queue_adapter = @original_queue_adapter
    travel_back
  end

  test "ranks named area matches above generic in-bounds coverage" do
    wire = NewsSource.create!(canonical_key: "wire-area-candidate", name: "Wire Source", source_kind: "wire")
    publisher = NewsSource.create!(canonical_key: "publisher-area-candidate", name: "Publisher", source_kind: "publisher")

    generic_article = NewsArticle.create!(
      news_source: publisher,
      url: "https://example.com/generic-port",
      canonical_url: "https://example.com/generic-port",
      title: "Port logistics remain steady in the gulf corridor",
      summary: "Shipping activity remains routine across nearby ports.",
      published_at: 2.hours.ago,
      content_scope: "core",
      metadata: { "transport_source" => "rss" }
    )
    NewsEvent.create!(
      news_source: publisher,
      news_article: generic_article,
      url: generic_article.url,
      title: generic_article.title,
      name: publisher.name,
      source: "rss",
      latitude: 26.1,
      longitude: 56.2,
      published_at: generic_article.published_at,
      fetched_at: generic_article.published_at,
      content_scope: "core"
    )

    named_article = NewsArticle.create!(
      news_source: wire,
      url: "https://example.com/hormuz-reroute",
      canonical_url: "https://example.com/hormuz-reroute",
      title: "Iran reroutes ships north of the Strait of Hormuz and studies new tolls",
      summary: "Shipping firms describe selective passage, rerouting, and toll-like fees through Hormuz.",
      published_at: 4.hours.ago,
      content_scope: "core",
      metadata: { "transport_source" => "api" }
    )
    NewsEvent.create!(
      news_source: wire,
      news_article: named_article,
      url: named_article.url,
      title: named_article.title,
      name: wire.name,
      source: "api",
      latitude: 35.0,
      longitude: 45.0,
      published_at: named_article.published_at,
      fetched_at: named_article.published_at,
      content_scope: "core"
    )

    candidates = AreaArticleCandidateService.new(@area, bounds: @area.bounds_hash).call

    assert_equal named_article.id, candidates.first[:event].news_article_id
    assert_includes candidates.first[:named_match_terms], "hormuz"
    assert_includes candidates.first[:profile_hits], "tolls"
  end

  test "enqueue_hydration queues top non-rss area candidates" do
    source = NewsSource.create!(canonical_key: "wire-hydrate-area", name: "Wire Source", source_kind: "wire")
    article = NewsArticle.create!(
      news_source: source,
      url: "https://example.com/hormuz-briefing",
      canonical_url: "https://example.com/hormuz-briefing",
      title: "Iran considers transit fees in Strait of Hormuz",
      summary: nil,
      published_at: 90.minutes.ago,
      content_scope: "core",
      metadata: { "transport_source" => "api" }
    )
    NewsEvent.create!(
      news_source: source,
      news_article: article,
      url: article.url,
      title: article.title,
      name: source.name,
      source: "api",
      latitude: 35.0,
      longitude: 45.0,
      published_at: article.published_at,
      fetched_at: article.published_at,
      content_scope: "core"
    )

    service = AreaArticleCandidateService.new(@area, bounds: @area.bounds_hash)

    assert_enqueued_with(job: RssArticleHydrationJob, args: [article.id]) do
      queued = service.enqueue_hydration!
      assert_equal 1, queued
    end

    article.reload
    assert_equal "queued", article.hydration_status
    assert_equal "area_candidate:maritime", article.metadata["force_hydration_reason"]
  end
end
