class RefreshNewsJob < ApplicationJob
  queue_as :default
  tracks_polling source: "gdelt", poll_type: "news"

  def perform
    NewsRefreshService.refresh_if_stale
  end
end
