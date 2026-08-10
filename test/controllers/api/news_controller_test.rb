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

  test "news response exposes the geocode family" do
    @news.update_columns(
      geocode_precision: "city",
      geocode_confidence: 0.912,
      geocode_basis: "title_place",
      geocode_country_code: "at",
      geocode_place_name: "Vienna"
    )

    get "/api/news"
    event = JSON.parse(response.body).find { |e| e["title"] == "Test news event" }

    assert_equal "city", event["geo_precision"]
    assert_in_delta 0.91, event["geo_confidence"], 0.001
    assert_equal "title_place", event["geo_basis"]
    assert_equal "at", event["geo_country_code"]
    assert_equal "Vienna", event["place_name"]
  end

  test "place_name is withheld for country-precision rows" do
    # geocode_place_name on a country centroid is routinely the publisher
    # ("Die Zeit", "NYT World"), so surfacing it would label a centroid with a
    # masthead. The coordinates are a whole country; there is no place to name.
    @news.update_columns(geocode_precision: "country", geocode_place_name: "Die Zeit")

    get "/api/news"
    event = JSON.parse(response.body).find { |e| e["title"] == "Test news event" }

    assert_nil event["place_name"]
    assert_equal "country", event["geo_precision"]
  end

  test "clustered response also carries the geocode family" do
    @news.update_columns(geocode_precision: "place", geocode_place_name: "Vienna")

    get "/api/news", params: { clustered: "true" }
    event = JSON.parse(response.body).find { |e| e["title"] == "Test news event" }

    assert_equal "place", event["geo_precision"]
    assert_equal "Vienna", event["place_name"]
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

  # content_scope gated claim extraction and clustering but never the map, so
  # two thirds of pins were headlines the scope classifier had already rejected.
  test "out_of_scope events are kept off the map" do
    scoped_event("news-ctrl-scope-out", "Local derby ends in a draw", scope: "out_of_scope")
    scoped_event("news-ctrl-scope-in", "Shelling reported near the border", scope: "core")

    get "/api/news"
    titles = JSON.parse(response.body).map { |entry| entry["title"] }

    assert_includes titles, "Shelling reported near the border"
    assert_not_includes titles, "Local derby ends in a draw"
  end

  # NewsArticle requires a scope, but a NewsEvent whose normalization returned no
  # ids has none. A plain `where.not` would drop these, because SQL evaluates
  # NOT (NULL = 'out_of_scope') to NULL rather than true.
  test "events with no content_scope still reach the map" do
    NewsEvent.create!(
      url: "https://example.com/news-ctrl-scope-nil", title: "Unclassified report",
      name: "Vienna", latitude: 48.2, longitude: 16.3, tone: -2.0, source: "example",
      content_scope: nil, published_at: 1.hour.ago, fetched_at: Time.current
    )

    get "/api/news"
    titles = JSON.parse(response.body).map { |entry| entry["title"] }

    assert_includes titles, "Unclassified report", "NULL scope is unknown, not out of scope"
  end

  test "serializes a prose summary and rejects feed tag lists" do
    scoped_event("news-ctrl-sum-good", "Quake hits the coast", scope: "core",
      summary: "A powerful earthquake struck the coast on Monday, killing at least eleven people and toppling homes.")
    scoped_event("news-ctrl-sum-tags", "Border incident reported", scope: "core",
      summary: "Rusija, Karas Ukrainoje")
    scoped_event("news-ctrl-sum-slug", "Strait transit resumes", scope: "core", summary: "us-iran")

    get "/api/news"
    by_title = JSON.parse(response.body).index_by { |entry| entry["title"] }

    assert_match(/powerful earthquake struck/, by_title["Quake hits the coast"]["summary"])
    assert_nil by_title["Border incident reported"]["summary"], "tag list is not a summary"
    assert_nil by_title["Strait transit resumes"]["summary"], "slug is not a summary"
  end

  # RSS descriptions arrive wrapped in markup. Measuring length before stripping
  # let a link block clear the minimum, then truncation cut the tag in half and
  # served a literal "<a…" as the standfirst.
  test "strips markup out of a summary before measuring or truncating it" do
    scoped_event("news-ctrl-sum-html", "Markup standfirst", scope: "core",
      summary: '<p>Rescue teams reached the village on Tuesday, according to officials.</p> <a href="https://example.com/more">Read more</a>')
    scoped_event("news-ctrl-sum-htmlonly", "Link only", scope: "core",
      summary: '<a href="https://example.com/a-very-long-tracking-url-that-is-plenty-long">Read more</a>')

    get "/api/news"
    by_title = JSON.parse(response.body).index_by { |entry| entry["title"] }

    summary = by_title["Markup standfirst"]["summary"]
    assert_equal "Rescue teams reached the village on Tuesday, according to officials. Read more", summary
    assert_no_match(/[<>]/, summary)
    assert_nil by_title["Link only"]["summary"], "a bare link is not a standfirst"
  end

  test "decodes entities and rejects comma-separated keyword lists" do
    scoped_event("news-ctrl-sum-ents", "Entity standfirst", scope: "core",
      summary: "Rescue teams reached the village&nbsp;&nbsp;on Tuesday, according to &quot;officials&quot;.")
    scoped_event("news-ctrl-sum-kw", "Keyword standfirst", scope: "core",
      summary: "North Korea, Russia, Ukraine, conflict, troops, missiles")

    get "/api/news"
    by_title = JSON.parse(response.body).index_by { |entry| entry["title"] }

    summary = by_title["Entity standfirst"]["summary"]
    assert_no_match(/&nbsp;|&quot;/, summary)
    assert_equal 'Rescue teams reached the village on Tuesday, according to "officials".', summary
    assert_nil by_title["Keyword standfirst"]["summary"], "keyword list is not a standfirst"
  end

  test "truncates a long summary on a sentence boundary" do
    long = "#{'The situation developed over several hours. ' * 8}Trailing clause that runs past the limit."
    scoped_event("news-ctrl-sum-long", "Long standfirst", scope: "core", summary: long)

    get "/api/news"
    entry = JSON.parse(response.body).find { |row| row["title"] == "Long standfirst" }

    assert_operator entry["summary"].length, :<=, 281
    assert entry["summary"].end_with?(".", "…"), "expected a clean cut, got #{entry['summary'][-20..].inspect}"
  end

  private

  def scoped_event(slug, title, scope:, summary: nil)
    source = NewsSource.find_or_create_by!(canonical_key: "publisher:example.com:#{slug}") do |row|
      row.name = "Example"
      row.source_kind = "publisher"
      row.publisher_domain = "example.com"
    end
    article = NewsArticle.create!(
      news_source: source,
      url: "https://example.com/#{slug}",
      canonical_url: "https://example.com/#{slug}",
      title: title, summary: summary, content_scope: scope,
      publisher_name: "Example", publisher_domain: "example.com",
      published_at: 1.hour.ago, fetched_at: Time.current
    )
    NewsEvent.create!(
      url: "https://example.com/#{slug}", title: title, name: "Vienna",
      latitude: 48.2, longitude: 16.3, tone: -2.0, source: "example",
      content_scope: scope, news_source: source, news_article: article,
      published_at: 1.hour.ago, fetched_at: Time.current
    )
  end
end
