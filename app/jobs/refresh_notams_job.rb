class RefreshNotamsJob < ApplicationJob
  queue_as :default

  def perform
    NotamRefreshService.refresh_if_stale
  end
end
