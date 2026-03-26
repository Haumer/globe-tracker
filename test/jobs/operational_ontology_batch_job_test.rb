require "test_helper"

class OperationalOntologyBatchJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    BackgroundRefreshScheduler.reset!
    clear_enqueued_jobs
  end

  test "enqueues insights refresh when operational records are stored" do
    flight = Flight.create!(
      icao24: "job123",
      callsign: "JOB123",
      latitude: 25.28,
      longitude: 55.31,
      updated_at: Time.current
    )

    assert_enqueued_with(job: RefreshInsightsSnapshotJob) do
      OperationalOntologyBatchJob.perform_now("flights", "ids" => [flight.id])
    end
  end
end
