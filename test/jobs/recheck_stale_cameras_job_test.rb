require "test_helper"

class RecheckStaleCamerasJobTest < ActiveSupport::TestCase
  test "is assigned to the background queue" do
    assert_equal "background", RecheckStaleCamerasJob.new.queue_name
  end

  test "calls CameraRefreshService.recheck_stale_cameras" do
    called = false
    mock = -> { called = true; nil }

    CameraRefreshService.stub(:recheck_stale_cameras, mock) do
      RecheckStaleCamerasJob.perform_now
    end

    assert called
  end
end
