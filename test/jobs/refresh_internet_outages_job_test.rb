require "test_helper"

class RefreshInternetOutagesJobTest < ActiveSupport::TestCase
  test "is assigned to the default queue" do
    assert_equal "default", RefreshInternetOutagesJob.new.queue_name
  end

  test "tracks polling with source internet-outages and poll_type internet_outages" do
    assert_equal "internet-outages", RefreshInternetOutagesJob.polling_source_resolver
    assert_equal "internet_outages", RefreshInternetOutagesJob.polling_type_resolver
  end

  test "calls InternetOutageRefreshService.refresh_if_stale" do
    called = false
    InternetOutageRefreshService.stub(:refresh_if_stale, -> { called = true; 3 }) do
      RefreshInternetOutagesJob.perform_now
    end
    assert called
  end
end
