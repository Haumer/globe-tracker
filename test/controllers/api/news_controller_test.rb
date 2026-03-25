require "test_helper"

class Api::NewsControllerTest < ActionDispatch::IntegrationTest
  setup do
    source = NewsSource.create!(
      canonical_key: "publisher:reuters.com",
      name: "Reuters",
      source_kind: "wire",
      publisher_domain: "reuters.com"
    )
    article = NewsArticle.create!(
      news_source: source,
      url: "https://example.com/news-ctrl-001",
      canonical_url: "https://example.com/news-ctrl-001",
      title: "Test news event",
      content_scope: "core",
      publisher_name: "Reuters",
      publisher_domain: "reuters.com",
      published_at: 2.hours.ago,
      fetched_at: Time.current
    )

    @news = NewsEvent.create!(
      url: "https://example.com/news-ctrl-001",
      name: "Vienna",
      title: "Test news event",
      latitude: 48.2,
      longitude: 16.3,
      tone: -2.5,
      level: "negative",
      category: "conflict",
      source: "reuters",
      content_scope: "core",
      news_source: source,
      news_article: article,
      published_at: 2.hours.ago,
      fetched_at: Time.current,
    )
    claim = NewsClaim.create!(
      news_article: article,
      event_family: "conflict",
      event_type: "military_action",
      claim_text: @news.title,
      confidence: 0.91,
      extraction_confidence: 0.9,
      actor_confidence: 0.91,
      event_confidence: 0.92,
      geo_confidence: 0.82,
      source_reliability: 0.92,
      verification_status: "single_source",
      geo_precision: "point",
      provenance: { "canonical_url" => article.canonical_url },
      published_at: @news.published_at
    )
    israel = NewsActor.create!(canonical_key: "state:il", name: "Israel", actor_type: "state", country_code: "IL")
    iran = NewsActor.create!(canonical_key: "state:ir", name: "Iran", actor_type: "state", country_code: "IR")
    NewsClaimActor.create!(news_claim: claim, news_actor: israel, role: "initiator", position: 0, confidence: 0.92)
    NewsClaimActor.create!(news_claim: claim, news_actor: iran, role: "target", position: 1, confidence: 0.89)
  end

  test "GET /api/news returns JSON array" do
    get "/api/news"
    assert_response :success

    data = JSON.parse(response.body)
    assert_kind_of Array, data
  end

  test "news response contains expected fields" do
    get "/api/news"
    data = JSON.parse(response.body)
    event = data.find { |e| e["title"] == "Test news event" }

    assert_not_nil event
    assert_equal "Vienna", event["name"]
    assert_in_delta 48.2, event["lat"], 0.01
    assert_in_delta 16.3, event["lng"], 0.01
    assert_equal "reuters", event["source"]
    assert_equal "Reuters", event["publisher"]
    assert_equal "core", event["content_scope"]
    assert_equal "conflict", event["claim_event_family"]
    assert_equal "military_action", event["claim_event_type"]
    assert_equal "single_source", event["claim_verification_status"]
    assert_equal "point", event["claim_geo_precision"]
    assert_equal [ "Israel", "Iran" ], event["actors"].map { |actor| actor["name"] }
    assert_equal "conflict", event["category"]
  end

  test "clustered mode groups by story_cluster_id" do
    NewsEvent.create!(
      url: "https://example.com/news-ctrl-002",
      title: "Same story different source",
      latitude: 48.2, longitude: 16.3,
      tone: -2.0, source: "bbc",
      story_cluster_id: "cluster-1",
      published_at: 1.hour.ago,
      fetched_at: Time.current,
    )
    NewsEvent.create!(
      url: "https://example.com/news-ctrl-003",
      title: "Same story third source",
      latitude: 48.2, longitude: 16.3,
      tone: -1.5, source: "ap",
      story_cluster_id: "cluster-1",
      published_at: 1.hour.ago,
      fetched_at: Time.current,
    )

    get "/api/news", params: { clustered: "true" }
    data = JSON.parse(response.body)
    cluster = data.find { |e| e["cluster_id"] == "cluster-1" }

    assert_not_nil cluster
    assert cluster["source_count"] >= 2
    assert_kind_of Array, cluster["sources"]
  end

  test "clustered mode keeps unclustered articles separate" do
    NewsEvent.create!(
      url: "https://example.com/news-ctrl-004",
      title: "Unclustered story one",
      latitude: 48.2, longitude: 16.3,
      tone: -2.0, source: "bbc",
      story_cluster_id: nil,
      published_at: 1.hour.ago,
      fetched_at: Time.current,
    )
    NewsEvent.create!(
      url: "https://example.com/news-ctrl-005",
      title: "Unclustered story two",
      latitude: 48.2, longitude: 16.3,
      tone: -1.5, source: "ap",
      story_cluster_id: nil,
      published_at: 1.hour.ago,
      fetched_at: Time.current,
    )

    get "/api/news", params: { clustered: "true" }
    data = JSON.parse(response.body)

    assert data.any? { |entry| entry["title"] == "Unclustered story one" }
    assert data.any? { |entry| entry["title"] == "Unclustered story two" }
  end
end
