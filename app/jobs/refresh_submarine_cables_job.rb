class RefreshSubmarineCablesJob < ApplicationJob
  queue_as :background
  tracks_polling source: "submarine-cables", poll_type: "submarine_cables"

  def perform
    SubmarineCableRefreshService.refresh_if_stale
  end
end
