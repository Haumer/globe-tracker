class RefreshNewsJob < ApplicationJob
  queue_as :default

  def perform
    NewsRefreshService.refresh_if_stale
  end
end
