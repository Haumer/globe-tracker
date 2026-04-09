require "test_helper"

class RefreshGeoconfirmedJobTest < ActiveSupport::TestCase
  test "is assigned to the background queue" do
    assert_equal "background", RefreshGeoconfirmedJob.new.queue_name
  end

  test "tracks polling with source geoconfirmed and poll_type geoconfirmed_events" do
    assert_equal "geoconfirmed", RefreshGeoconfirmedJob.polling_source_resolver
    assert_equal "geoconfirmed_events", RefreshGeoconfirmedJob.polling_type_resolver
  end

  test "calls GeoconfirmedRefreshService.refresh_if_stale" do
    called = false
    GeoconfirmedRefreshService.stub(:refresh_if_stale, -> { called = true; 8 }) do
      RefreshGeoconfirmedJob.perform_now
    end
    assert called
  end
end
