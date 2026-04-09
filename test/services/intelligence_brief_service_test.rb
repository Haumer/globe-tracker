require "test_helper"

class IntelligenceBriefServiceTest < ActiveSupport::TestCase
  setup do
    @original_key = ENV["ANTHROPIC_API_KEY"]
    ENV["ANTHROPIC_API_KEY"] = nil
    @original_cache_store = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown do
    ENV["ANTHROPIC_API_KEY"] = @original_key
    Rails.cache = @original_cache_store
  end

  test "generate returns nil when ANTHROPIC_API_KEY is not set" do
    result = IntelligenceBriefService.generate

    assert_nil result
  end

  test "generate returns cached result when available and not forced" do
    cached = { brief: "cached brief", generated_at: Time.current.iso8601 }
    Rails.cache.write("intelligence_brief", cached, expires_in: 6.hours)

    result = IntelligenceBriefService.generate

    assert_not_nil result
    assert_equal "cached brief", result[:brief]
  end

  test "generate force bypasses cache" do
    ENV["ANTHROPIC_API_KEY"] = "test-key-123"
    cached = { brief: "old cached brief", generated_at: Time.current.iso8601 }
    Rails.cache.write("intelligence_brief", cached, expires_in: 6.hours)

    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .to_return(
        status: 200,
        body: { content: [{ text: "NEW brief" }] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    result = IntelligenceBriefService.generate(force: true)

    assert_not_nil result
    assert_equal "NEW brief", result[:brief]
  end

  test "generate returns nil when Claude returns nil" do
    ENV["ANTHROPIC_API_KEY"] = "test-key-123"

    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .to_return(status: 500, body: "Internal Server Error")

    result = IntelligenceBriefService.generate(force: true)

    assert_nil result
  end

  test "generate caches successful result" do
    ENV["ANTHROPIC_API_KEY"] = "test-key-123"

    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .to_return(
        status: 200,
        body: { content: [{ text: "cached brief" }] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    IntelligenceBriefService.generate(force: true)

    cached = Rails.cache.read("intelligence_brief")
    assert_not_nil cached
    assert_equal "cached brief", cached[:brief]
  end

  test "invalidate clears the cache" do
    Rails.cache.write("intelligence_brief", { brief: "old" })

    IntelligenceBriefService.invalidate

    assert_nil Rails.cache.read("intelligence_brief")
  end

  test "call_claude sends correct headers" do
    stub = stub_request(:post, "https://api.anthropic.com/v1/messages")
      .with(
        headers: {
          "x-api-key" => "test-key-abc",
          "anthropic-version" => "2023-06-01",
          "Content-Type" => "application/json",
        }
      )
      .to_return(
        status: 200,
        body: { content: [{ text: "response" }] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    IntelligenceBriefService.send(:call_claude, "test-key-abc", "test prompt")

    assert_requested stub
  end

  test "call_claude returns nil on network error" do
    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .to_raise(Errno::ECONNREFUSED)

    result = IntelligenceBriefService.send(:call_claude, "key", "prompt")

    assert_nil result
  end

  test "call_claude returns nil on HTTP error" do
    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .to_return(status: 500, body: "Internal Server Error")

    result = IntelligenceBriefService.send(:call_claude, "key", "prompt")

    assert_nil result
  end

  test "call_claude extracts text from successful response" do
    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .to_return(
        status: 200,
        body: { content: [{ text: "Brief content here" }] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    result = IntelligenceBriefService.send(:call_claude, "key", "prompt")

    assert_equal "Brief content here", result
  end

  test "MODEL constant is defined" do
    assert_not_nil IntelligenceBriefService::MODEL
  end

  test "MAX_TOKENS constant is defined" do
    assert_equal 4000, IntelligenceBriefService::MAX_TOKENS
  end

  test "generate result includes context_summary" do
    ENV["ANTHROPIC_API_KEY"] = "test-key-123"

    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .to_return(
        status: 200,
        body: { content: [{ text: "CRITICAL brief" }] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    result = IntelligenceBriefService.generate(force: true)

    assert_not_nil result
    assert result.key?(:context_summary)
    assert result[:context_summary].key?(:conflict_zones)
    assert result[:context_summary].key?(:earthquakes)
    assert result[:context_summary].key?(:outages)
    assert result[:context_summary].key?(:fires)
    assert result[:context_summary].key?(:news_articles)
    assert result[:context_summary].key?(:gps_jamming)
  end
end
