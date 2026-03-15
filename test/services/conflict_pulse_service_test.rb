require "test_helper"

class ConflictPulseServiceTest < ActiveSupport::TestCase
  setup do
    Rails.cache.clear
  end

  test "returns empty array with no conflict news" do
    result = ConflictPulseService.analyze
    assert_equal [], result
  end

  test "detects pulse zone from clustered conflict news" do
    10.times do |i|
      NewsEvent.create!(
        url: "https://example.com/conflict-#{i}",
        title: "Fighting escalates in region #{i}",
        latitude: 49.0 + rand * 0.5,
        longitude: 35.0 + rand * 0.5,
        tone: -5.0 - rand,
        category: "conflict",
        source: ["reuters", "bbc", "aljazeera", "cnn", "guardian"][i % 5],
        published_at: (i * 2).hours.ago,
        fetched_at: Time.current,
      )
    end

    result = ConflictPulseService.analyze

    assert result.any?, "Should detect at least one pulse zone"
    zone = result.first
    assert zone[:pulse_score] >= 20
    assert_includes %w[surging escalating elevated baseline], zone[:escalation_trend]
    assert zone[:count_24h] > 0
    assert zone[:top_headlines].any?
    assert zone[:source_count] > 1
  end

  test "filters out cells with fewer than MIN_ARTICLES" do
    2.times do |i|
      NewsEvent.create!(
        url: "https://example.com/sparse-#{i}",
        title: "Minor incident #{i}",
        latitude: -30.0,
        longitude: 25.0,
        tone: -2.0,
        category: "conflict",
        source: "reuters",
        published_at: i.hours.ago,
        fetched_at: Time.current,
      )
    end

    result = ConflictPulseService.analyze
    assert_empty result
  end

  test "spike ratio increases score when frequency surges" do
    # Baseline: 1 article per day for 5 days
    5.times do |i|
      NewsEvent.create!(
        url: "https://example.com/base-#{i}",
        title: "Ongoing tension #{i}",
        latitude: 15.0,
        longitude: 45.0,
        tone: -3.0,
        category: "conflict",
        source: "reuters",
        published_at: (2 + i).days.ago,
        fetched_at: Time.current,
      )
    end

    # Surge: 8 articles today
    8.times do |i|
      NewsEvent.create!(
        url: "https://example.com/surge-#{i}",
        title: "Major escalation event #{i}",
        latitude: 15.0 + rand * 0.3,
        longitude: 45.0 + rand * 0.3,
        tone: -6.0 - rand,
        category: "conflict",
        source: ["reuters", "bbc", "aljazeera", "france24"][i % 4],
        published_at: (i * 2).hours.ago,
        fetched_at: Time.current,
      )
    end

    result = ConflictPulseService.analyze
    assert result.any?
    zone = result.first
    assert zone[:spike_ratio] > 2.0, "Spike ratio should reflect frequency surge"
    assert_includes %w[surging escalating], zone[:escalation_trend]
  end

  test "cross-layer signals boost score" do
    5.times do |i|
      NewsEvent.create!(
        url: "https://example.com/cross-#{i}",
        title: "Conflict with military activity #{i}",
        latitude: 50.0,
        longitude: 35.0,
        tone: -4.0,
        category: "conflict",
        source: ["reuters", "bbc", "cnn"][i % 3],
        published_at: (i * 3).hours.ago,
        fetched_at: Time.current,
      )
    end

    # Add military flights in the same area
    3.times do |i|
      Flight.create!(
        icao24: "pulse-mil-#{i}",
        callsign: "FORTE#{i}",
        latitude: 50.5,
        longitude: 35.5,
        altitude: 40000,
        origin_country: "US",
        military: true,
      )
    end

    result = ConflictPulseService.analyze
    assert result.any?
    zone = result.first
    assert zone[:cross_layer_signals][:military_flights], "Should detect military flights"
  end

  test "caches results when cache store supports it" do
    cache = ActiveSupport::Cache::MemoryStore.new
    5.times do |i|
      NewsEvent.create!(
        url: "https://example.com/cache-#{i}",
        title: "Cached conflict #{i}",
        latitude: 10.0, longitude: 10.0,
        tone: -4.0, category: "conflict",
        source: "reuters", published_at: i.hours.ago,
        fetched_at: Time.current,
      )
    end

    first = cache.fetch(ConflictPulseService::CACHE_KEY, expires_in: 10.minutes) { ConflictPulseService.new.compute }
    assert first.any?

    NewsEvent.delete_all
    second = cache.fetch(ConflictPulseService::CACHE_KEY, expires_in: 10.minutes) { ConflictPulseService.new.compute }
    assert_equal first, second
  end
end
