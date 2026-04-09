require "test_helper"

class RefreshGpsJammingJobTest < ActiveSupport::TestCase
  test "is assigned to the default queue" do
    assert_equal "default", RefreshGpsJammingJob.new.queue_name
  end

  test "tracks polling with source gps-jamming and poll_type gps_jamming" do
    assert_equal "gps-jamming", RefreshGpsJammingJob.polling_source_resolver
    assert_equal "gps_jamming", RefreshGpsJammingJob.polling_type_resolver
  end

  test "calls GpsJammingRefreshService.refresh_if_stale" do
    called = false
    GpsJammingRefreshService.stub(:refresh_if_stale, -> { called = true; 15 }) do
      RefreshGpsJammingJob.perform_now
    end
    assert called
  end
end
