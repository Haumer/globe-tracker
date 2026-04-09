require "test_helper"

class RefreshCamerasJobTest < ActiveSupport::TestCase
  test "is assigned to the default queue" do
    assert_equal "default", RefreshCamerasJob.new.queue_name
  end

  test "tracks polling with source cameras and poll_type webcams" do
    assert_equal "cameras", RefreshCamerasJob.polling_source_resolver
    assert_equal "webcams", RefreshCamerasJob.polling_type_resolver
  end

  test "instantiates CameraRefreshService with bbox and calls refresh" do
    bbox = { "north" => 50.0, "south" => 40.0, "east" => 20.0, "west" => 10.0 }
    refresh_called = false
    fake_service = Object.new
    fake_service.define_singleton_method(:refresh) { refresh_called = true; 5 }

    CameraRefreshService.stub(:new, ->(**_kwargs) { fake_service }) do
      RefreshCamerasJob.perform_now(bbox)
    end

    assert refresh_called, "Expected refresh to be called on CameraRefreshService instance"
  end
end
