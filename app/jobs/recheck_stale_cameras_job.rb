class RecheckStaleCamerasJob < ApplicationJob
  queue_as :background

  def perform
    CameraRefreshService.recheck_stale_cameras
  end
end
