require "test_helper"

class NewsSourceAdapterTest < ActiveSupport::TestCase
  test "normalizes adapter output into the shared contract" do
    result = NewsSourceAdapter.normalize!(
      source_adapter: "test_feed",
      attrs: {
        url: "https://example.com/story",
        title: " Example headline ",
        summary: "  Example summary  ",
        name: "Example Feed",
        country: "US",
        tone: "-2.5",
        published_at: "2026-03-24T12:00:00Z",
        category: "world",
        themes: ["conflict", "conflict", nil],
        source: "api",
        metadata: { provider_id: "abc123", ignored: nil },
      }
    )

    assert_equal "test_feed", result[:source_adapter]
    assert_equal "https://example.com/story", result[:url]
    assert_equal "Example headline", result[:title]
    assert_equal "Example summary", result[:summary]
    assert_equal "Example Feed", result[:name]
    assert_equal "US", result[:country]
    assert_equal(-2.5, result[:tone])
    assert_equal "world", result[:category]
    assert_equal ["conflict"], result[:themes]
    assert_equal({ "provider_id" => "abc123" }, result[:metadata])
  end

  test "requires url and title" do
    assert_raises(ArgumentError) do
      NewsSourceAdapter.normalize!(source_adapter: "bad", attrs: { title: "Missing URL" })
    end
  end
end
