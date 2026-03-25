require "test_helper"

class GlobalPollerServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    ServiceRuntimeState.where(service_name: "poller").delete_all
    Rails.cache.clear
    clear_enqueued_jobs
    clear_performed_jobs
    ActiveJob::Base.queue_adapter = :test
  end

  teardown do
    Rails.cache = @original_cache
  end

  test "tick enqueues the jobs due at the current cadence boundary" do
    travel_to Time.zone.parse("2026-03-25 10:00:00 UTC") do
      result = GlobalPollerService.tick!

      assert_equal "running", result[:status]
      assert_operator result[:jobs_enqueued], :>, 0
      assert_includes result[:job_names], "PollOpenskyJob"
      assert_includes result[:job_names], "RefreshEarthquakesJob"
      assert_includes result[:job_names], "RefreshNewsJob"
      assert_includes result[:job_names], "RefreshWeatherAlertsJob"
      refute_includes result[:job_names], "PollAdsbMilitaryJob"
      refute_includes result[:job_names], "RefreshRssNewsJob"

      status = GlobalPollerService.status
      assert status[:running]
      assert_equal(ENV["AISSTREAM_API_KEY"].present? ? "stream" : "disabled", status[:ais_mode])
      assert_equal "poller", status[:scheduler]
      assert_equal 1, status[:poll_count]
    end
  end

  test "tick enqueues staggered one-minute jobs later in the cycle" do
    travel_to Time.zone.parse("2026-03-25 10:00:00 UTC") do
      GlobalPollerService.tick!
    end

    clear_enqueued_jobs

    travel_to Time.zone.parse("2026-03-25 10:00:15 UTC") do
      result = GlobalPollerService.tick!
      assert_includes result[:job_names], "PollAdsbMilitaryJob"
      refute_includes result[:job_names], "PollOpenskyJob"
    end

    clear_enqueued_jobs

    travel_to Time.zone.parse("2026-03-25 10:00:30 UTC") do
      result = GlobalPollerService.tick!
      assert_includes result[:job_names], "RefreshLiveTrainsJob"
      refute_includes result[:job_names], "PollAdsbMilitaryJob"
    end
  end

  test "tick does not enqueue duplicates within the same cadence slot" do
    travel_to Time.zone.parse("2026-03-25 10:00:00 UTC") do
      first = GlobalPollerService.tick!
      first_count = enqueued_jobs.size

      second = GlobalPollerService.tick!

      assert_equal "running", first[:status]
      assert_equal "running", second[:status]
      assert_equal first_count, enqueued_jobs.size
      assert_equal 2, GlobalPollerService.status[:poll_count]
    end
  end

  test "tick respects five minute offsets for news jobs" do
    travel_to Time.zone.parse("2026-03-25 10:00:00 UTC") do
      GlobalPollerService.tick!
    end

    clear_enqueued_jobs

    travel_to Time.zone.parse("2026-03-25 10:01:00 UTC") do
      result = GlobalPollerService.tick!

      assert_includes result[:job_names], "RefreshRssNewsJob"
      refute_includes result[:job_names], "RefreshNewsJob"
    end
  end

  test "tick respects paused state" do
    PollerRuntimeState.request_pause!

    travel_to Time.zone.parse("2026-03-25 10:00:00 UTC") do
      result = GlobalPollerService.tick!

      assert_equal "paused", result[:status]
      assert_equal 0, result[:jobs_enqueued]
      assert_enqueued_jobs 0
      assert GlobalPollerService.paused?
    end
  end

  test "tick respects stopped state" do
    PollerRuntimeState.request_stop!

    travel_to Time.zone.parse("2026-03-25 10:00:00 UTC") do
      result = GlobalPollerService.tick!

      assert_equal "stopped", result[:status]
      assert_equal 0, result[:jobs_enqueued]
      assert_enqueued_jobs 0
      assert_equal true, GlobalPollerService.status[:stopped]
    end
  end
end
