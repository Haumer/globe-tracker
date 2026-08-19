require "test_helper"

class NewsRefreshServiceTest < ActiveSupport::TestCase
  test "extract_title_from_url with slug-based URL" do
    service = NewsRefreshService.new
    title = service.send(:extract_title_from_url, "https://example.com/2024/03/earthquake-hits-central-turkey")
    assert_equal "Earthquake Hits Central Turkey", title
  end

  test "extract_title_from_url returns nil for short slug" do
    service = NewsRefreshService.new
    title = service.send(:extract_title_from_url, "https://example.com/abc")
    assert_nil title
  end

  test "extract_title_from_url returns nil for numeric-only slug" do
    service = NewsRefreshService.new
    title = service.send(:extract_title_from_url, "https://example.com/12345678")
    assert_nil title
  end

  test "extract_title_from_url strips file extension" do
    service = NewsRefreshService.new
    title = service.send(:extract_title_from_url, "https://example.com/major-storm-hits-coast.html")
    assert_equal "Major Storm Hits Coast", title
  end

  test "extract_title_from_url handles underscores" do
    service = NewsRefreshService.new
    title = service.send(:extract_title_from_url, "https://example.com/breaking_news_from_europe")
    assert_equal "Breaking News From Europe", title
  end

  # Regression: conflict-query rows carry latitude: nil, and refresh used to
  # upsert them unconditionally -- so a URL that RSS or a sitemap had already
  # geocoded got its coordinates overwritten with nil and its geocode_* columns
  # reset to defaults. Known URLs must be skipped, new ones still inserted.
  test "refresh does not overwrite an existing geocoded event with a nil-coordinate conflict row" do
    existing = NewsEvent.create!(
      url: "https://example.com/beirut-explosion-kills-three",
      title: "Beirut explosion kills three",
      source: "rss",
      latitude: 33.8938,
      longitude: 35.5018,
      geocode_place_name: "Beirut",
      geocode_basis: "title_place",
      geocode_precision: "city",
      geocode_kind: "event",
      geocode_confidence: 0.9,
      published_at: Time.current,
      fetched_at: Time.current
    )

    now = Time.current
    conflict_record = lambda do |url, title|
      {
        url: url, name: "example.com", title: title,
        latitude: nil, longitude: nil,
        tone: -3.0, level: "elevated", category: "conflict",
        themes: [ "ARMEDCONFLICT" ], published_at: now, fetched_at: now,
        source: "gdelt", credibility: "tier2/low", created_at: now, updated_at: now,
      }
    end
    conflict_result = {
      records: [
        conflict_record.call(existing.url, existing.title),
        conflict_record.call("https://example.com/new-strike-hits-port-city", "Strike hits port city"),
      ],
      ingest_items: [],
    }

    service = NewsRefreshService.new
    stored = service.stub(:gdelt_get, nil) do
      service.stub(:fetch_conflict_queries, ->(_seen, _now) { conflict_result }) do
        service.refresh
      end
    end

    assert_equal 1, stored

    existing.reload
    assert_in_delta 33.8938, existing.latitude
    assert_equal "title_place", existing.geocode_basis
    assert_equal "rss", existing.source

    created = NewsEvent.find_by(url: "https://example.com/new-strike-hits-port-city")
    assert_not_nil created
    assert_nil created.latitude
  end
end
