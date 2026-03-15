require "test_helper"

class Api::ConflictPulseControllerTest < ActionDispatch::IntegrationTest
  setup do
    Rails.cache.clear
  end

  test "index returns zones array" do
    get "/api/conflict_pulse"
    assert_response :success
    data = JSON.parse(response.body)
    assert_kind_of Array, data["zones"]
    assert_kind_of Integer, data["count"]
  end

  test "index returns pulse zones when conflict news exists" do
    6.times do |i|
      NewsEvent.create!(
        url: "https://example.com/pulse-test-#{i}",
        title: "Conflict event #{i}",
        latitude: 33.0, longitude: 44.0,
        tone: -5.0, category: "conflict",
        source: ["reuters", "bbc", "cnn"][i % 3],
        published_at: (i * 2).hours.ago,
        fetched_at: Time.current,
      )
    end

    get "/api/conflict_pulse"
    assert_response :success
    data = JSON.parse(response.body)
    assert data["count"] > 0
    zone = data["zones"].first
    assert zone["pulse_score"] >= 20
    assert zone["top_headlines"].any?
  end
end
