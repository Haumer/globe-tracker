class RefreshInternetTrafficJob < ApplicationJob
  queue_as :default
  tracks_polling source: "cloudflare-radar", poll_type: "internet_traffic"

  def perform
    CloudflareRadarService.refresh_if_stale
  end
end
