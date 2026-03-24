require "test_helper"

class NewsClaimRecorderTest < ActiveSupport::TestCase
  test "records claim rows and actor roles for an article" do
    source = NewsSource.create!(
      canonical_key: "publisher:bbc.com",
      name: "BBC",
      source_kind: "publisher",
      publisher_domain: "bbc.com"
    )
    article = NewsArticle.create!(
      news_source: source,
      url: "https://www.bbc.com/news/articles/example-claim",
      canonical_url: "https://www.bbc.com/news/articles/example-claim",
      title: "Israel strikes Iran nuclear sites",
      publisher_name: "BBC",
      publisher_domain: "bbc.com",
      published_at: Time.utc(2026, 3, 24, 12, 0, 0),
      fetched_at: Time.utc(2026, 3, 24, 12, 5, 0)
    )

    mapping = NewsClaimRecorder.record_all([
      {
        news_article_id: article.id,
        title: article.title,
        published_at: article.published_at,
      },
    ])

    claim = NewsClaim.find_by!(news_article_id: article.id)
    claim_actors = claim.news_claim_actors.includes(:news_actor)

    assert_equal claim.id, mapping[article.id]
    assert_equal "conflict", claim.event_family
    assert_equal "ground_operation", claim.event_type
    assert_equal [ "Israel", "Iran" ], claim_actors.map { |row| row.news_actor.name }
    assert_equal [ "initiator", "target" ], claim_actors.map(&:role)
  end

  test "backfill_missing only creates claims for unclaimed articles" do
    source = NewsSource.create!(
      canonical_key: "publisher:reuters.com",
      name: "Reuters",
      source_kind: "wire",
      publisher_domain: "reuters.com"
    )
    article = NewsArticle.create!(
      news_source: source,
      url: "https://www.reuters.com/world/example-backfill",
      canonical_url: "https://www.reuters.com/world/example-backfill",
      title: "Iran and Israel hold talks in Oman",
      publisher_name: "Reuters",
      publisher_domain: "reuters.com",
      published_at: Time.utc(2026, 3, 24, 12, 0, 0),
      fetched_at: Time.utc(2026, 3, 24, 12, 5, 0)
    )

    total = NewsClaimRecorder.backfill_missing(batch_size: 10)

    assert_equal 1, total
    assert_equal 1, NewsClaim.where(news_article_id: article.id).count
  end

  test "does not create claims for out of scope articles" do
    source = NewsSource.create!(
      canonical_key: "publisher:food.com",
      name: "Food",
      source_kind: "publisher",
      publisher_domain: "food.com"
    )
    article = NewsArticle.create!(
      news_source: source,
      url: "https://food.com/recipes/pasta-night",
      canonical_url: "https://food.com/recipes/pasta-night",
      title: "Best pasta recipes for a quick dinner",
      publisher_name: "Food",
      publisher_domain: "food.com",
      content_scope: "out_of_scope",
      published_at: Time.utc(2026, 3, 24, 12, 0, 0),
      fetched_at: Time.utc(2026, 3, 24, 12, 5, 0)
    )

    mapping = NewsClaimRecorder.record_all([
      {
        news_article_id: article.id,
        title: article.title,
        published_at: article.published_at,
        content_scope: "out_of_scope",
      },
    ])

    assert_empty mapping
    assert_nil NewsClaim.find_by(news_article_id: article.id)
  end

  test "rebuild_all refreshes claims using article summaries" do
    source = NewsSource.create!(
      canonical_key: "publisher:state.gov",
      name: "State",
      source_kind: "publisher",
      publisher_domain: "state.gov"
    )
    article = NewsArticle.create!(
      news_source: source,
      url: "https://state.gov/talks-oman",
      canonical_url: "https://state.gov/talks-oman",
      title: "Talks resume in Oman",
      summary: "Iran and the United States will meet next week in Muscat.",
      publisher_name: "State",
      publisher_domain: "state.gov",
      content_scope: "adjacent",
      published_at: Time.utc(2026, 3, 24, 12, 0, 0),
      fetched_at: Time.utc(2026, 3, 24, 12, 5, 0)
    )

    total = NewsClaimRecorder.rebuild_all(batch_size: 10)
    claim = NewsClaim.find_by!(news_article_id: article.id)

    assert_equal 1, total
    assert_equal "diplomacy", claim.event_family
    assert_equal "negotiation", claim.event_type
  end
end
