class RefreshMultiNewsJob < ApplicationJob
  queue_as :default
  tracks_polling source: "multi-news", poll_type: "news"

  def perform
    MultiNewsService.refresh_if_stale
  end
end
