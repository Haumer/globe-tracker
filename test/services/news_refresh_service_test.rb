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
end
