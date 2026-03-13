class RefreshCamerasJob < ApplicationJob
  queue_as :default

  def perform(bbox = {}, sources: nil)
    CameraRefreshService.new(
      north: bbox[:north] || bbox["north"],
      south: bbox[:south] || bbox["south"],
      east:  bbox[:east]  || bbox["east"],
      west:  bbox[:west]  || bbox["west"],
      sources: sources,
    ).refresh
  end
end
