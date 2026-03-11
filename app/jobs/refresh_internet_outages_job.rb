class RefreshInternetOutagesJob < ApplicationJob
  queue_as :default

  def perform
    InternetOutageRefreshService.refresh_if_stale
  end
end
