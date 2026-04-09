require "test_helper"

class RefreshLiveTrainsJobTest < ActiveSupport::TestCase
  test "is assigned to the fast_live queue" do
    assert_equal "fast_live", RefreshLiveTrainsJob.new.queue_name
  end

  test "tracks polling with source hafas and poll_type trains" do
    assert_equal "hafas", RefreshLiveTrainsJob.polling_source_resolver
    assert_equal "trains", RefreshLiveTrainsJob.polling_type_resolver
  end

  test "skips when trains layer is disabled" do
    called = false
    TrainRefreshService.stub(:refresh_if_stale, -> { called = true; 10 }) do
      LayerAvailability.stub(:enabled?, ->(key) { key.to_s == "trains" ? false : true }) do
        RefreshLiveTrainsJob.perform_now
      end
    end
    refute called, "Expected TrainRefreshService.refresh_if_stale NOT to be called when trains disabled"
  end

  test "calls TrainRefreshService.refresh_if_stale when trains layer is enabled" do
    called = false
    TrainRefreshService.stub(:refresh_if_stale, -> { called = true; 10 }) do
      LayerAvailability.stub(:enabled?, ->(_key) { true }) do
        RefreshLiveTrainsJob.perform_now
      end
    end
    assert called, "Expected TrainRefreshService.refresh_if_stale to be called"
  end

  test "skips stale job on fast_live queue" do
    job = RefreshLiveTrainsJob.new
    job.enqueued_at = 2.minutes.ago.iso8601

    TrainRefreshService.stub(:refresh_if_stale, -> { raise "should not be called" }) do
      LayerAvailability.stub(:enabled?, ->(_key) { true }) do
        result = job.perform_now
        assert_equal false, result
      end
    end
  end
end
