require "test_helper"

class AreaBriefServiceTest < ActiveSupport::TestCase
  test "maritime brief prefers selective passage over naive open transit" do
    user = User.create!(email: "brief-test@example.com", password: "password123")
    area = user.area_workspaces.create!(
      name: "Strait of Hormuz",
      scope_type: "preset_region",
      profile: "maritime",
      bounds: { lamin: 24.0, lamax: 28.0, lomin: 54.0, lomax: 58.5 },
      scope_metadata: { region_key: "strait-of-hormuz", region_name: "Strait of Hormuz" },
      default_layers: ["ships", "chokepoints", "news"]
    )

    wire = NewsSource.create!(canonical_key: "reuters-like", name: "Wire Source", source_kind: "wire")
    publisher = NewsSource.create!(canonical_key: "regional-paper", name: "Regional Paper", source_kind: "publisher")

    toll_article = NewsArticle.create!(
      news_source: wire,
      url: "https://example.com/tolls",
      canonical_url: "https://example.com/tolls",
      title: "Iran considers levying transit fees on ships in Hormuz",
      summary: "Recent reporting describes Tehran monetizing passage and requiring selective permission for some vessels.",
      published_at: 2.hours.ago,
      content_scope: "core",
      hydration_status: "hydrated"
    )
    NewsEvent.create!(
      news_source: wire,
      news_article: toll_article,
      url: toll_article.url,
      title: toll_article.title,
      name: wire.name,
      source: "rss",
      latitude: 26.4,
      longitude: 56.2,
      published_at: toll_article.published_at,
      fetched_at: toll_article.published_at,
      content_scope: "core"
    )

    allowed_article = NewsArticle.create!(
      news_source: publisher,
      url: "https://example.com/allowed",
      canonical_url: "https://example.com/allowed",
      title: "Iran agreed to allow 20 more ships through Strait of Hormuz",
      summary: "The arrangement is framed as selective passage rather than a fully open corridor.",
      published_at: 90.minutes.ago,
      content_scope: "core",
      hydration_status: "hydrated"
    )
    NewsEvent.create!(
      news_source: publisher,
      news_article: allowed_article,
      url: allowed_article.url,
      title: allowed_article.title,
      name: publisher.name,
      source: "rss",
      latitude: 26.3,
      longitude: 56.4,
      published_at: allowed_article.published_at,
      fetched_at: allowed_article.published_at,
      content_scope: "core"
    )

    transit_article = NewsArticle.create!(
      news_source: publisher,
      url: "https://example.com/safe-transit",
      canonical_url: "https://example.com/safe-transit",
      title: "Two tankers clear Strait of Hormuz safely",
      summary: "Two vessels safely transited the route.",
      published_at: 70.minutes.ago,
      content_scope: "adjacent",
      hydration_status: "hydrated"
    )
    NewsEvent.create!(
      news_source: publisher,
      news_article: transit_article,
      url: transit_article.url,
      title: transit_article.title,
      name: publisher.name,
      source: "rss",
      latitude: 26.35,
      longitude: 56.1,
      published_at: transit_article.published_at,
      fetched_at: transit_article.published_at,
      content_scope: "adjacent"
    )

    brief = AreaBriefService.new(area, bounds: area.bounds_hash).call

    assert_equal "restricted_selective", brief[:status]
    assert_match(/does not look fully open/i, brief[:summary])
    assert brief[:evidence].any? { |item| item[:title].include?("transit fees") }
    assert brief[:evidence].any? { |item| item[:title].include?("allow 20 more ships") }
  end
end
