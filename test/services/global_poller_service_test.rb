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

    travel_to Time.zone.parse("2026-03-25 10:00:05 UTC") do
      result = GlobalPollerService.tick!
      assert_includes result[:job_names], "PollAdsbMilitaryJob"
      refute_includes result[:job_names], "PollOpenskyJob"
    end

    clear_enqueued_jobs

    travel_to Time.zone.parse("2026-03-25 10:00:10 UTC") do
      result = GlobalPollerService.tick!
      refute_includes result[:job_names], "RefreshLiveTrainsJob"
      refute_includes result[:job_names], "PollAdsbMilitaryJob"
    end
  end

  test "tick enqueues rotating regional adsb jobs on the fast live cadence" do
    travel_to Time.zone.parse("2026-03-25 10:00:20 UTC") do
      result = GlobalPollerService.tick!

      assert_includes result[:job_names], "PollAdsbRegionJob(europe)"
      refute_includes result[:job_names], "PollOpenskyJob"
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

  # Hazards and theaters run on separate offsets so neither waits on the other,
  # and neither shares a slot with the graph sweeps that used to precede them.
  test "tick enqueues hazard relationship sync on its offset" do
    travel_to Time.zone.parse("2026-03-25 10:07:00 UTC") do
      result = GlobalPollerService.tick!

      assert_includes result[:job_names], "SyncHazardRelationshipsJob"
      refute_includes result[:job_names], "SyncTheaterRelationshipsJob"
      refute_includes result[:job_names], "RefreshInsightsSnapshotJob"
    end
  end

  test "tick enqueues theater relationship sync on its own later offset" do
    travel_to Time.zone.parse("2026-03-25 10:09:00 UTC") do
      result = GlobalPollerService.tick!

      assert_includes result[:job_names], "SyncTheaterRelationshipsJob"
      refute_includes result[:job_names], "SyncHazardRelationshipsJob"
    end
  end

  # The live half of the v2 graph keeps a ten-minute cadence; the reference half
  # runs twice a day, matching how often its source tables actually change.
  test "tick enqueues the live ontology v2 chain every ten minutes" do
    travel_to Time.zone.parse("2026-03-25 10:03:00 UTC") do
      assert_enqueued_with(job: OntologyV2BackfillJob, args: [{ stage: "event_graph" }]) do
        GlobalPollerService.tick!
      end
    end
  end

  test "tick enqueues the reference ontology v2 chain twice a day" do
    travel_to Time.zone.parse("2026-03-25 05:00:00 UTC") do
      assert_enqueued_with(job: OntologyV2BackfillJob, args: [{ stage: "identity" }]) do
        GlobalPollerService.tick!
      end
    end
  end

  test "tick does not start the reference chain on the live chain's slot" do
    travel_to Time.zone.parse("2026-03-25 10:03:00 UTC") do
      GlobalPollerService.tick!

      started = enqueued_jobs.select { |job| job[:job] == OntologyV2BackfillJob }
        .map { |job| job[:args].first["stage"] }

      assert_equal ["event_graph"], started
    end
  end

  test "tick skips minute-level refresh duplicates while one is still pending" do
    travel_to Time.zone.parse("2026-03-25 10:00:00 UTC") do
      result = GlobalPollerService.tick!
      assert_includes result[:job_names], "RefreshNewsJob"
    end

    clear_enqueued_jobs

    travel_to Time.zone.parse("2026-03-25 10:05:00 UTC") do
      result = GlobalPollerService.tick!
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
