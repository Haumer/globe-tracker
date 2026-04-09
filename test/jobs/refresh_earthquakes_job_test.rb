require "test_helper"

class RefreshEarthquakesJobTest < ActiveSupport::TestCase
  test "is assigned to the default queue" do
    assert_equal "default", RefreshEarthquakesJob.new.queue_name
  end

  test "tracks polling with source usgs and poll_type earthquakes" do
    assert_equal "usgs", RefreshEarthquakesJob.polling_source_resolver
    assert_equal "earthquakes", RefreshEarthquakesJob.polling_type_resolver
  end

  test "calls EarthquakeRefreshService.refresh_if_stale" do
    called = false
    EarthquakeRefreshService.stub(:refresh_if_stale, -> { called = true; 7 }) do
      RefreshEarthquakesJob.perform_now
    end
    assert called
  end
end
