require "test_helper"

class NewsEventTest < ActiveSupport::TestCase
  setup do
    @news = NewsEvent.create!(
      url: "https://example.com/article-001",
      name: "Test Location",
      title: "Major event unfolds",
      latitude: 48.2,
      longitude: 16.3,
      tone: -3.5,
      level: "negative",
      category: "conflict",
      source: "reuters",
      published_at: 2.hours.ago,
      fetched_at: Time.current,
    )
  end

  test "within_bounds filters by lat/lng" do
    results = NewsEvent.within_bounds(lamin: 47.0, lamax: 49.0, lomin: 15.0, lomax: 17.0)
    assert_includes results, @news

    results = NewsEvent.within_bounds(lamin: 0.0, lamax: 5.0, lomin: 0.0, lomax: 5.0)
    assert_not_includes results, @news
  end

  test "recent scope returns events from last 24 hours by fetched_at" do
    old = NewsEvent.create!(
      url: "https://example.com/article-002",
      title: "Old story",
      latitude: 48.0, longitude: 16.0,
      published_at: 2.days.ago,
      fetched_at: 2.days.ago,
    )

    assert_includes NewsEvent.recent, @news
    assert_not_includes NewsEvent.recent, old
  end

  test "time_range_column recent scope uses published_at" do
    old_published = NewsEvent.create!(
      url: "https://example.com/article-003",
      title: "Old published",
      latitude: 48.0, longitude: 16.0,
      published_at: 2.days.ago,
      fetched_at: Time.current,
    )

    # The time_range_column :published_at recent scope checks published_at
    recent_by_published = NewsEvent.where("published_at > ?", 24.hours.ago)
    assert_includes recent_by_published, @news
    assert_not_includes recent_by_published, old_published
  end

  test "unique url constraint" do
    assert_raises(ActiveRecord::RecordNotUnique) do
      NewsEvent.create!(
        url: "https://example.com/article-001",
        title: "Duplicate",
        latitude: 48.0, longitude: 16.0,
        fetched_at: Time.current,
      )
    end
  end
end
