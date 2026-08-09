class RefreshNewsSitemapJob < ApplicationJob
  queue_as :default
  tracks_polling source: "news_sitemap", poll_type: "news"

  def perform
    NewsSitemapService.refresh_if_stale
  end
end
