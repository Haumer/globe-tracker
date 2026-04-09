require "test_helper"

class PollOpenskyJobTest < ActiveSupport::TestCase
  test "is assigned to the fast_live queue" do
    assert_equal "fast_live", PollOpenskyJob.new.queue_name
  end

  test "tracks polling with source opensky and poll_type flights" do
    assert_equal "opensky", PollOpenskyJob.polling_source_resolver
    assert_equal "flights", PollOpenskyJob.polling_type_resolver
  end

  test "calls OpenskyService.fetch_flights with empty bounds" do
    called_with = nil
    mock = ->(**kwargs) { called_with = kwargs; %w[f1 f2 f3] }

    OpenskyService.stub(:fetch_flights, mock) do
      result = PollOpenskyJob.perform_now
      assert_equal 3, result
    end

    assert_equal({}, called_with[:bounds])
  end

  test "skips stale job on fast_live queue" do
    job = PollOpenskyJob.new
    job.enqueued_at = 2.minutes.ago.iso8601

    OpenskyService.stub(:fetch_flights, ->(**_kw) { raise "should not be called" }) do
      result = job.perform_now
      assert_equal false, result
    end
  end
end
