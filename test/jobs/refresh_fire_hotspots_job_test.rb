require "test_helper"

class RefreshFireHotspotsJobTest < ActiveSupport::TestCase
  test "is assigned to the default queue" do
    assert_equal "default", RefreshFireHotspotsJob.new.queue_name
  end

  test "tracks polling with source firms and poll_type fire_hotspots" do
    assert_equal "firms", RefreshFireHotspotsJob.polling_source_resolver
    assert_equal "fire_hotspots", RefreshFireHotspotsJob.polling_type_resolver
  end

  test "calls FirmsRefreshService.refresh_if_stale" do
    called = false
    FirmsRefreshService.stub(:refresh_if_stale, -> { called = true; 20 }) do
      RefreshFireHotspotsJob.perform_now
    end
    assert called
  end
end
