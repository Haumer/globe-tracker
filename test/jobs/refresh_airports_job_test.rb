require "test_helper"

class RefreshAirportsJobTest < ActiveSupport::TestCase
  test "is assigned to the background queue" do
    assert_equal "background", RefreshAirportsJob.new.queue_name
  end

  test "tracks polling with source ourairports and poll_type airports" do
    assert_equal "ourairports", RefreshAirportsJob.polling_source_resolver
    assert_equal "airports", RefreshAirportsJob.polling_type_resolver
  end

  test "calls OurAirportsService.refresh_if_stale" do
    called = false
    OurAirportsService.stub(:refresh_if_stale, -> { called = true; 10 }) do
      RefreshAirportsJob.perform_now
    end
    assert called
  end
end
