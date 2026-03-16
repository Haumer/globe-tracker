class RefreshRssNewsJob < ApplicationJob
  queue_as :default

  def perform
    RssNewsService.refresh_if_stale
  end
end
