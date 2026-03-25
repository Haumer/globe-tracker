class RssArticleHydrationJob < ApplicationJob
  queue_as :background

  def perform(news_article_id)
    RssArticleHydrationService.hydrate(news_article_id)
  end
end
