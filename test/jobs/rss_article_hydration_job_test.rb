require "test_helper"

class RssArticleHydrationJobTest < ActiveSupport::TestCase
  test "is assigned to the background queue" do
    assert_equal "background", RssArticleHydrationJob.new.queue_name
  end

  test "calls RssArticleHydrationService.hydrate with news_article_id" do
    called_with = nil
    mock = ->(id) { called_with = id; nil }

    RssArticleHydrationService.stub(:hydrate, mock) do
      RssArticleHydrationJob.perform_now(42)
    end

    assert_equal 42, called_with
  end
end
