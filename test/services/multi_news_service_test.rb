require "test_helper"

class MultiNewsServiceTest < ActiveSupport::TestCase
  setup do
    @service = MultiNewsService.new
  end

  test "sentiment_to_tone converts sentiment to tone scale" do
    assert_in_delta 0.0, MultiNewsService.sentiment_to_tone(nil), 0.01
    assert_in_delta 5.0, MultiNewsService.sentiment_to_tone(0.5), 0.01
    assert_in_delta(-10.0, MultiNewsService.sentiment_to_tone(-1.0), 0.01)
    assert_in_delta 10.0, MultiNewsService.sentiment_to_tone(1.0), 0.01
  end

  test "build_record returns a complete hash" do
    record = @service.send(:build_record,
      url: "https://example.com/news/1",
      title: "Test Article",
      name: "Test Source",
      lat: 48.2,
      lng: 16.3,
      tone: -3.5,
      published_at: Time.current,
      themes: ["conflict", "military"],
      source: "worldnews"
    )

    assert_equal "https://example.com/news/1", record[:url]
    assert_equal "Test Article", record[:title]
    assert_equal "Test Source", record[:name]
    assert_in_delta 48.2, record[:latitude], 0.01
    assert_in_delta 16.3, record[:longitude], 0.01
    assert_in_delta(-3.5, record[:tone], 0.01)
    assert_equal "worldnews", record[:source]
    assert_kind_of Array, record[:themes]
    assert_not_nil record[:level]
    assert_not_nil record[:fetched_at]
    assert_not_nil record[:created_at]
  end

  test "parse_time handles valid ISO string" do
    result = @service.send(:parse_time, "2025-06-15T12:00:00Z")
    assert_kind_of Time, result
    assert_equal 2025, result.year
  end

  test "parse_time returns nil for blank input" do
    assert_nil @service.send(:parse_time, nil)
    assert_nil @service.send(:parse_time, "")
  end

  test "parse_time returns nil for invalid input" do
    assert_nil @service.send(:parse_time, "not-a-date")
  end

  test "stale? returns true when no cache entry" do
    Rails.cache.delete("multi_news_last_fetch")
    assert MultiNewsService.stale?
  end

  test "API_SOURCES is a non-empty array" do
    assert_kind_of Array, MultiNewsService::API_SOURCES
    assert MultiNewsService::API_SOURCES.size > 0
  end
end
