class RefreshNotamsJob < ApplicationJob
  queue_as :default
  tracks_polling source: "notams", poll_type: "notams"

  def perform
    NotamRefreshService.refresh_if_stale
  end
end
