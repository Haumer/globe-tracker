require "test_helper"

class NewsStoryClustererTest < ActiveSupport::TestCase
  test "clusters the same conflict incident across multiple sources" do
    article_a = create_article(
      suffix: "cluster-a",
      publisher: "BBC",
      domain: "bbc.com",
      title: "Israel strikes targets near Isfahan",
      source_kind: "publisher",
      published_at: Time.utc(2026, 3, 24, 12, 0, 0)
    )
    article_b = create_article(
      suffix: "cluster-b",
      publisher: "Reuters",
      domain: "reuters.com",
      title: "Explosions heard in central Iran after suspected Israeli attack",
      source_kind: "wire",
      published_at: Time.utc(2026, 3, 24, 13, 0, 0)
    )

    create_claim(article_a, family: "conflict", event_type: "airstrike", claim_text: article_a.title)
    create_claim(article_b, family: "conflict", event_type: "missile_attack", claim_text: article_b.title)

    event_a = create_event(article_a, title: article_a.title, location_name: "Isfahan", lat: 32.65, lng: 51.67)
    event_b = create_event(article_b, title: article_b.title, location_name: "Isfahan", lat: 32.64, lng: 51.70)

    records = [
      {
        news_article_id: article_a.id,
        title: event_a.title,
        name: event_a.name,
        latitude: event_a.latitude,
        longitude: event_a.longitude,
        published_at: event_a.published_at,
        content_scope: "core",
        news_source_id: article_a.news_source_id,
      },
      {
        news_article_id: article_b.id,
        title: event_b.title,
        name: event_b.name,
        latitude: event_b.latitude,
        longitude: event_b.longitude,
        published_at: event_b.published_at,
        content_scope: "core",
        news_source_id: article_b.news_source_id,
      },
    ]

    NewsStoryClusterer.assign_records(records)

    cluster_key = event_a.reload.story_cluster_id
    assert_not_nil cluster_key
    assert cluster_key.present?
    assert_equal cluster_key, event_b.reload.story_cluster_id

    cluster = NewsStoryCluster.find_by!(cluster_key: cluster_key)
    assert_equal 2, cluster.article_count
    assert_equal 2, cluster.source_count
    assert_equal "multi_source", cluster.verification_status
    assert_operator cluster.source_reliability, :>, 0.7
    assert_operator cluster.geo_confidence, :>, 0.7
    assert_equal "point", cluster.geo_precision
    assert_includes %w[airstrike missile_attack], cluster.event_type
  end

  test "separates diplomacy from conflict even with the same actors" do
    conflict_article = create_article(
      suffix: "cluster-c",
      publisher: "BBC",
      domain: "bbc.com",
      title: "Israel strikes targets near Isfahan",
      source_kind: "publisher",
      published_at: Time.utc(2026, 3, 24, 12, 0, 0)
    )
    diplomacy_article = create_article(
      suffix: "cluster-d",
      publisher: "Reuters",
      domain: "reuters.com",
      title: "Iran and Israel exchange messages through mediators",
      source_kind: "wire",
      published_at: Time.utc(2026, 3, 24, 14, 0, 0)
    )

    create_claim(conflict_article, family: "conflict", event_type: "airstrike", claim_text: conflict_article.title)
    create_claim(diplomacy_article, family: "diplomacy", event_type: "negotiation", claim_text: diplomacy_article.title)

    conflict_event = create_event(conflict_article, title: conflict_article.title, location_name: "Isfahan", lat: 32.65, lng: 51.67)
    diplomacy_event = create_event(diplomacy_article, title: diplomacy_article.title, location_name: "Muscat", lat: 23.59, lng: 58.41)

    records = [
      {
        news_article_id: conflict_article.id,
        title: conflict_event.title,
        name: conflict_event.name,
        latitude: conflict_event.latitude,
        longitude: conflict_event.longitude,
        published_at: conflict_event.published_at,
        content_scope: "core",
        news_source_id: conflict_article.news_source_id,
      },
      {
        news_article_id: diplomacy_article.id,
        title: diplomacy_event.title,
        name: diplomacy_event.name,
        latitude: diplomacy_event.latitude,
        longitude: diplomacy_event.longitude,
        published_at: diplomacy_event.published_at,
        content_scope: "core",
        news_source_id: diplomacy_article.news_source_id,
      },
    ]

    NewsStoryClusterer.assign_records(records)

    refute_equal conflict_event.reload.story_cluster_id, diplomacy_event.reload.story_cluster_id
    assert_equal 2, NewsStoryCluster.count
  end

  test "reclustering the same article is idempotent" do
    article = create_article(
      suffix: "cluster-recluster",
      publisher: "Reuters",
      domain: "reuters.com",
      title: "Explosions heard in central Iran after suspected Israeli attack",
      source_kind: "wire",
      published_at: Time.utc(2026, 3, 24, 13, 0, 0)
    )

    create_claim(article, family: "conflict", event_type: "missile_attack", claim_text: article.title)
    create_event(article, title: article.title, location_name: "Isfahan", lat: 32.64, lng: 51.70)

    first_cluster_key = NewsStoryClusterer.recluster_article(article)
    second_cluster_key = NewsStoryClusterer.recluster_article(article)

    assert_equal first_cluster_key, second_cluster_key
    assert_equal 1, NewsStoryCluster.count
    assert_equal 1, NewsStoryMembership.count
    assert_equal first_cluster_key, article.news_events.first.reload.story_cluster_id
  end

  private

  def create_article(suffix:, publisher:, domain:, title:, source_kind:, published_at:)
    source = NewsSource.create!(
      canonical_key: "publisher:#{domain}:#{suffix}",
      name: publisher,
      source_kind: source_kind,
      publisher_domain: domain
    )

    NewsArticle.create!(
      news_source: source,
      url: "https://#{domain}/#{suffix}",
      canonical_url: "https://#{domain}/#{suffix}",
      title: title,
      summary: title,
      content_scope: "core",
      publisher_name: publisher,
      publisher_domain: domain,
      published_at: published_at,
      fetched_at: published_at + 5.minutes
    )
  end

  def create_event(article, title:, location_name:, lat:, lng:)
    NewsEvent.create!(
      news_article: article,
      news_source: article.news_source,
      url: article.url,
      title: title,
      name: location_name,
      latitude: lat,
      longitude: lng,
      tone: -3.0,
      level: "elevated",
      category: "conflict",
      source: article.publisher_domain,
      content_scope: article.content_scope,
      published_at: article.published_at,
      fetched_at: article.fetched_at
    )
  end

  def create_claim(article, family:, event_type:, claim_text:)
    claim = NewsClaim.create!(
      news_article: article,
      event_family: family,
      event_type: event_type,
      claim_text: claim_text,
      confidence: 0.92,
      extraction_confidence: 0.91,
      actor_confidence: 0.92,
      event_confidence: 0.93,
      geo_confidence: 0.82,
      source_reliability: article.news_source.source_kind == "wire" ? 0.92 : 0.74,
      verification_status: "single_source",
      geo_precision: "point",
      extraction_method: "heuristic",
      extraction_version: "headline_rules_v2",
      published_at: article.published_at,
      provenance: { "canonical_url" => article.canonical_url }
    )

    israel = NewsActor.find_or_create_by!(canonical_key: "state:il") do |actor|
      actor.name = "Israel"
      actor.actor_type = "state"
      actor.country_code = "IL"
    end
    iran = NewsActor.find_or_create_by!(canonical_key: "state:ir") do |actor|
      actor.name = "Iran"
      actor.actor_type = "state"
      actor.country_code = "IR"
    end

    NewsClaimActor.create!(news_claim: claim, news_actor: israel, role: "initiator", position: 0, confidence: 0.93)
    NewsClaimActor.create!(news_claim: claim, news_actor: iran, role: family == "diplomacy" ? "participant" : "target", position: 1, confidence: 0.91)
  end
end
