class RefreshSectorInputsJob < ApplicationJob
  queue_as :background
  tracks_polling source: "sector-inputs", poll_type: "sector_inputs"

  def perform
    SectorInputRefreshService.refresh_if_stale
  end
end
