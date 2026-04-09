require "test_helper"

class RefreshInternetTrafficJobTest < ActiveSupport::TestCase
  test "is assigned to the default queue" do
    assert_equal "default", RefreshInternetTrafficJob.new.queue_name
  end

  test "tracks polling with source cloudflare-radar and poll_type internet_traffic" do
    assert_equal "cloudflare-radar", RefreshInternetTrafficJob.polling_source_resolver
    assert_equal "internet_traffic", RefreshInternetTrafficJob.polling_type_resolver
  end

  test "calls CloudflareRadarService.refresh_if_stale" do
    called = false
    CloudflareRadarService.stub(:refresh_if_stale, -> { called = true; 10 }) do
      RefreshInternetTrafficJob.perform_now
    end
    assert called
  end
end
