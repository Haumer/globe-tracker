class RefreshLiveTrainsJob < ApplicationJob
  queue_as :fast_live
  tracks_polling source: "hafas", poll_type: "trains"

  def perform
    return unless LayerAvailability.enabled?(:trains)

    TrainRefreshService.refresh_if_stale
  end
end
