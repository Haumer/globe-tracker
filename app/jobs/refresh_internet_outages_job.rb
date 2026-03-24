class RefreshInternetOutagesJob < ApplicationJob
  queue_as :default
  tracks_polling source: "internet-outages", poll_type: "internet_outages"

  def perform
    InternetOutageRefreshService.refresh_if_stale
  end
end
