require "test_helper"

class NewsScopeBackfillServiceTest < ActiveSupport::TestCase
  test "rebuckets articles and events and removes out of scope claims" do
    source = NewsSource.create!(
      canonical_key: "publisher:example.com",
      name: "Example",
      source_kind: "publisher",
      publisher_domain: "example.com"
    )

    recipe_article = NewsArticle.create!(
      news_source: source,
      url: "https://example.com/recipe",
      canonical_url: "https://example.com/recipe",
      title: "Best pasta recipes for a quick dinner",
      summary: "Chef tips for a perfect brunch",
      publisher_name: "Example",
      publisher_domain: "example.com",
      content_scope: "adjacent",
      published_at: Time.utc(2026, 3, 24, 10, 0, 0),
      fetched_at: Time.utc(2026, 3, 24, 10, 5, 0)
    )
    core_article = NewsArticle.create!(
      news_source: source,
      url: "https://example.com/strike",
      canonical_url: "https://example.com/strike",
      title: "Israel strikes Iran nuclear sites",
      summary: "Officials report a military escalation",
      publisher_name: "Example",
      publisher_domain: "example.com",
      content_scope: "adjacent",
      published_at: Time.utc(2026, 3, 24, 11, 0, 0),
      fetched_at: Time.utc(2026, 3, 24, 11, 5, 0)
    )

    NewsEvent.create!(
      news_article: recipe_article,
      source: "rss",
      title: recipe_article.title,
      url: recipe_article.url,
      latitude: 0.0,
      longitude: 0.0,
      published_at: recipe_article.published_at,
      fetched_at: recipe_article.fetched_at,
      content_scope: nil
    )
    NewsEvent.create!(
      news_article: core_article,
      source: "rss",
      title: core_article.title,
      url: core_article.url,
      latitude: 1.0,
      longitude: 1.0,
      published_at: core_article.published_at,
      fetched_at: core_article.fetched_at,
      content_scope: "adjacent"
    )
    orphan_event = NewsEvent.create!(
      source: "rss",
      title: "Celebrity feud explodes after red carpet interview",
      url: "https://example.com/celebrity-feud",
      latitude: 2.0,
      longitude: 2.0,
      published_at: Time.utc(2026, 3, 24, 12, 0, 0),
      fetched_at: Time.utc(2026, 3, 24, 12, 5, 0),
      content_scope: nil
    )

    stale_claim = NewsClaim.create!(
      news_article: recipe_article,
      event_family: "general",
      event_type: "actor_mention",
      claim_text: recipe_article.title,
      confidence: 0.4,
      extraction_method: "heuristic",
      extraction_version: "test_seed",
      primary: true,
      metadata: {},
      published_at: recipe_article.published_at
    )
    stale_actor = NewsActor.create!(
      canonical_key: "state:ir",
      name: "Iran",
      actor_type: "state",
      country_code: "IR",
      metadata: {}
    )
    NewsClaimActor.create!(
      news_claim: stale_claim,
      news_actor: stale_actor,
      role: "subject",
      position: 0,
      confidence: 0.4,
      matched_text: "Iran",
      metadata: {}
    )

    NewsClaimRecorder.record_all([
      {
        news_article_id: core_article.id,
        title: core_article.title,
        published_at: core_article.published_at,
        content_scope: "adjacent",
      },
    ])

    summary = NewsScopeBackfillService.run(batch_size: 10)

    assert_equal "out_of_scope", recipe_article.reload.content_scope
    assert_equal "core", core_article.reload.content_scope
    assert_equal [ "core", "out_of_scope", "out_of_scope" ], NewsEvent.order(:id).pluck(:content_scope).sort
    assert_equal "out_of_scope", orphan_event.reload.content_scope
    assert_nil NewsClaim.find_by(news_article_id: recipe_article.id)
    assert_equal "ground_operation", NewsClaim.find_by!(news_article_id: core_article.id).event_type
    assert_equal 1, summary[:deleted_claims]
    assert_equal 2, summary[:article_updates]
    assert_equal 3, summary[:event_updates]
  end
end
