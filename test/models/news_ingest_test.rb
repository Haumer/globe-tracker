require "test_helper"

class NewsIngestTest < ActiveSupport::TestCase
  setup do
    @ingest = NewsIngest.create!(
      source_feed: "gdelt",
      source_endpoint_url: "https://api.gdelt.org/v2/doc",
      fetched_at: Time.current,
      payload_format: "json",
      content_hash: "abc123unique"
    )
  end

  test "valid creation" do
    assert @ingest.persisted?
  end

  test "source_feed is required" do
    r = NewsIngest.new(source_endpoint_url: "https://x.com", fetched_at: Time.current, payload_format: "json", content_hash: "x")
    assert_not r.valid?
    assert_includes r.errors[:source_feed], "can't be blank"
  end

  test "source_endpoint_url is required" do
    r = NewsIngest.new(source_feed: "gdelt", fetched_at: Time.current, payload_format: "json", content_hash: "x")
    assert_not r.valid?
    assert_includes r.errors[:source_endpoint_url], "can't be blank"
  end

  test "fetched_at is required" do
    r = NewsIngest.new(source_feed: "gdelt", source_endpoint_url: "https://x.com", payload_format: "json", content_hash: "x")
    assert_not r.valid?
    assert_includes r.errors[:fetched_at], "can't be blank"
  end

  test "payload_format is required" do
    r = NewsIngest.new(source_feed: "gdelt", source_endpoint_url: "https://x.com", fetched_at: Time.current, content_hash: "x")
    assert_not r.valid?
    assert_includes r.errors[:payload_format], "can't be blank"
  end

  test "content_hash is required" do
    r = NewsIngest.new(source_feed: "gdelt", source_endpoint_url: "https://x.com", fetched_at: Time.current, payload_format: "json")
    assert_not r.valid?
    assert_includes r.errors[:content_hash], "can't be blank"
  end

  test "has_many news_articles" do
    assert_respond_to @ingest, :news_articles
  end

  test "has_many news_events" do
    assert_respond_to @ingest, :news_events
  end
end
