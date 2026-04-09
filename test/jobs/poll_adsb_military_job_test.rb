require "test_helper"

class PollAdsbMilitaryJobTest < ActiveSupport::TestCase
  test "is assigned to the fast_live queue" do
    assert_equal "fast_live", PollAdsbMilitaryJob.new.queue_name
  end

  test "tracks polling with source adsb-military and poll_type flights" do
    assert_equal "adsb-military", PollAdsbMilitaryJob.polling_source_resolver
    assert_equal "flights", PollAdsbMilitaryJob.polling_type_resolver
  end

  test "calls AdsbService.fetch_military" do
    called = false
    mock = -> { called = true; %w[a b c] }

    AdsbService.stub(:fetch_military, mock) do
      result = PollAdsbMilitaryJob.perform_now
      assert_equal 3, result
    end

    assert called
  end

  test "skips stale job on fast_live queue" do
    job = PollAdsbMilitaryJob.new
    job.enqueued_at = 2.minutes.ago.iso8601

    AdsbService.stub(:fetch_military, -> { raise "should not be called" }) do
      # The job should be aborted before calling the service
      result = job.perform_now
      assert_equal false, result
    end
  end
end
