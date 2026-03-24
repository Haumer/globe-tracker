class RefreshRssNewsJob < ApplicationJob
  queue_as :default
  tracks_polling source: "rss", poll_type: "news"

  def perform
    RssNewsService.refresh_if_stale
  end
end
