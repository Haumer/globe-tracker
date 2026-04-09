require "test_helper"

class SourceFeedStatusTest < ActiveSupport::TestCase
  setup do
    @feed = SourceFeedStatus.create!(
      feed_key: "gdelt_news",
      provider: "gdelt",
      display_name: "GDELT News Feed",
      feed_kind: "news",
      status: "success"
    )
  end

  test "valid creation" do
    assert @feed.persisted?
  end

  test "feed_key is required" do
    r = SourceFeedStatus.new(provider: "x", display_name: "X", feed_kind: "news", status: "success")
    assert_not r.valid?
    assert_includes r.errors[:feed_key], "can't be blank"
  end

  test "provider is required" do
    r = SourceFeedStatus.new(feed_key: "x", display_name: "X", feed_kind: "news", status: "success")
    assert_not r.valid?
    assert_includes r.errors[:provider], "can't be blank"
  end

  test "display_name is required" do
    r = SourceFeedStatus.new(feed_key: "x", provider: "x", feed_kind: "news", status: "success")
    assert_not r.valid?
    assert_includes r.errors[:display_name], "can't be blank"
  end

  test "feed_kind is required" do
    r = SourceFeedStatus.new(feed_key: "x", provider: "x", display_name: "X", status: "success")
    assert_not r.valid?
    assert_includes r.errors[:feed_kind], "can't be blank"
  end

  test "status is required" do
    r = SourceFeedStatus.new(feed_key: "x", provider: "x", display_name: "X", feed_kind: "news")
    r.status = nil
    assert_not r.valid?
    assert_includes r.errors[:status], "can't be blank"
  end

  test "active_first scope prioritizes errors first" do
    error_feed = SourceFeedStatus.create!(
      feed_key: "error_feed", provider: "test", display_name: "Error",
      feed_kind: "news", status: "error"
    )
    results = SourceFeedStatus.active_first
    assert_operator results.index(error_feed), :<, results.index(@feed)
  end
end
