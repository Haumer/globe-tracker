require "test_helper"

class Api::NewsControllerTest < ActionDispatch::IntegrationTest
  setup do
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
      published_at: 2.hours.ago,
      fetched_at: Time.current,
    )
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
end
