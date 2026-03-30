require "test_helper"

class AreaImpactAssessmentServiceTest < ActiveSupport::TestCase
  setup do
    travel_to Time.utc(2026, 3, 31, 10, 0, 0)

    @user = User.create!(email: "impact-area@example.com", password: "password123")
    @area = @user.area_workspaces.create!(
      name: "Gulf States",
      scope_type: "preset_region",
      profile: "maritime",
      bounds: { lamin: 21.0, lamax: 32.0, lomin: 44.0, lomax: 58.5 },
      scope_metadata: { region_key: "gulf-states", region_name: "Gulf States" },
      default_layers: ["ships", "chokepoints", "news", "militaryFlights"]
    )
  end

  teardown do
    travel_back
  end

  test "turns troop reporting into linked maritime infrastructure and market impacts" do
    source = NewsSource.create!(canonical_key: "wire-impact-area", name: "Wire Source", source_kind: "wire")
    article = NewsArticle.create!(
      news_source: source,
      url: "https://example.com/gulf-deployment",
      canonical_url: "https://example.com/gulf-deployment",
      title: "US deploys more troops to Gulf staging bases as Iran tensions rise",
      summary: "The deployment raises concern around shipping lanes, export terminals, and oil flows through nearby chokepoints.",
      published_at: 90.minutes.ago,
      content_scope: "core",
      hydration_status: "hydrated",
      metadata: { "transport_source" => "api" }
    )
    NewsClaim.create!(
      news_article: article,
      event_family: "conflict",
      event_type: "ground_operation",
      claim_text: article.title,
      confidence: 0.9,
      extraction_confidence: 0.9,
      actor_confidence: 0.8,
      event_confidence: 0.92,
      geo_confidence: 0.8,
      source_reliability: 0.82,
      verification_status: "single_source",
      geo_precision: "point",
      extraction_method: "heuristic",
      extraction_version: "headline_rules_v2",
      published_at: article.published_at,
      provenance: { "canonical_url" => article.canonical_url }
    )
    NewsEvent.create!(
      news_source: source,
      news_article: article,
      url: article.url,
      title: article.title,
      name: source.name,
      source: "api",
      latitude: 26.1,
      longitude: 53.6,
      published_at: article.published_at,
      fetched_at: article.published_at,
      content_scope: "core"
    )

    impacts = AreaImpactAssessmentService.new(
      @area,
      bounds: @area.bounds_hash,
      movement: {
        flights_total: 18,
        flights_military: 7,
        flights_emergency: 1,
        ships_total: 14,
        ships_destinations: 11,
        trains_total: 0,
        trains_on_track: 0,
        notams_total: 16,
      },
      assets: {
        chokepoints: 1,
        airports: 4,
        military_bases: 3,
        cameras: 0,
        power_plants: 6,
      },
      chokepoints: [
        {
          name: "Strait of Hormuz",
          status: "critical",
          ships_nearby: { total: 18, tankers: 6 },
          flows: { oil: { pct: 21 } },
          commodity_signals: [
            { symbol: "OIL_BRENT", name: "Brent Crude", change_pct: 2.6, flow_pct: 21 },
            { symbol: "LNG", name: "LNG", change_pct: 1.4, flow_pct: 30 },
          ],
        },
      ],
      situations: [{ situation_name: "Iran Theater", pulse_score: 82 }],
      insights: [{ title: "Military flight surge", severity: "high" }]
    ).call

    domains = impacts.map { |impact| impact[:domain] }

    assert_includes domains, "military_posture"
    assert_includes domains, "maritime_passage"
    assert_includes domains, "infrastructure_exposure"
    assert_includes domains, "market_pressure"

    military = impacts.find { |impact| impact[:domain] == "military_posture" }
    assert_match(/force reinforcement|combat activity/i, military[:summary])
    assert_includes military[:linked_domains], "Maritime Passage"
    assert_equal "US deploys more troops to Gulf staging bases as Iran tensions rise", military[:evidence].first[:title]

    market = impacts.find { |impact| impact[:domain] == "market_pressure" }
    assert_match(/Brent Crude/i, market[:summary])
    assert_match(/\+2\.60%/, market[:metrics].find { |metric| metric[:label] == "Largest move" }[:value])
  end
end
