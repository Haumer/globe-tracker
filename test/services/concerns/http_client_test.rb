require "test_helper"
require "webmock/minitest"

class HttpClientTest < ActiveSupport::TestCase
  # Test harness: create a simple class that extends HttpClient
  class FakeService
    extend HttpClient

    def self.name
      "FakeService"
    end
  end

  test "http_get returns parsed JSON on success" do
    stub_request(:get, "https://example.com/data")
      .to_return(status: 200, body: '{"ok": true}', headers: { "Content-Type" => "application/json" })

    result = FakeService.http_get(URI("https://example.com/data"), retries: 0)
    assert_equal({ "ok" => true }, result)
  end

  test "http_get returns nil on 500 with no retries" do
    stub_request(:get, "https://example.com/data")
      .to_return(status: 500, body: "Internal Server Error")

    result = FakeService.http_get(URI("https://example.com/data"), retries: 0)
    assert_nil result
  end

  test "http_get retries on failure and succeeds on second attempt" do
    stub_request(:get, "https://example.com/data")
      .to_return(status: 500, body: "fail")
      .then.to_return(status: 200, body: '{"retry": "ok"}', headers: { "Content-Type" => "application/json" })

    result = FakeService.http_get(URI("https://example.com/data"), retries: 1, retry_delay: 0.01)
    assert_equal({ "retry" => "ok" }, result)
  end

  test "http_get caches successful response and serves stale on failure" do
    cache_key = "test:http_cache:#{SecureRandom.hex(4)}"

    # Use a real memory store for this test since test env uses null_store
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    stub_request(:get, "https://example.com/cached")
      .to_return(status: 200, body: '{"cached": true}', headers: { "Content-Type" => "application/json" })

    # First call — caches result
    result = FakeService.http_get(URI("https://example.com/cached"), retries: 0, cache_key: cache_key, cache_ttl: 1.minute)
    assert_equal({ "cached" => true }, result)

    # Stub failure for next call
    stub_request(:get, "https://example.com/cached")
      .to_return(status: 500, body: "fail")

    # Second call — serves from cache
    result = FakeService.http_get(URI("https://example.com/cached"), retries: 0, cache_key: cache_key, cache_ttl: 1.minute)
    assert_equal({ "cached" => true }, result)
  ensure
    Rails.cache = original_cache
  end

  test "http_get returns nil when no cache and all retries exhausted" do
    stub_request(:get, "https://example.com/nocache")
      .to_return(status: 503, body: "unavailable")

    result = FakeService.http_get(URI("https://example.com/nocache"), retries: 1, retry_delay: 0.01)
    assert_nil result
  end

  test "http_post returns parsed JSON on success" do
    stub_request(:post, "https://example.com/submit")
      .to_return(status: 200, body: '{"submitted": true}', headers: { "Content-Type" => "application/json" })

    result = FakeService.http_post(URI("https://example.com/submit"), form_data: { key: "val" }, retries: 0)
    assert_equal({ "submitted" => true }, result)
  end

  test "http_post returns nil on failure" do
    stub_request(:post, "https://example.com/submit")
      .to_return(status: 422, body: "Unprocessable")

    result = FakeService.http_post(URI("https://example.com/submit"), form_data: { key: "val" }, retries: 0)
    assert_nil result
  end
end
