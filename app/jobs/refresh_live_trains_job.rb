class RefreshLiveTrainsJob < ApplicationJob
  queue_as :fast_live
  tracks_polling source: "hafas", poll_type: "trains"

  def perform
    TrainRefreshService.refresh_if_stale
  end
end
