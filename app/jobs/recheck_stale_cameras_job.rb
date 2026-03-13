class RecheckStaleCamerasJob < ApplicationJob
  queue_as :default

  def perform
    CameraRefreshService.recheck_stale_cameras
  end
end
