require "test_helper"

class WarmSituationLayersJobTest < ActiveJob::TestCase
  # The job's contract is modest: never raise, report what it warmed. The
  # per-situation plan logic has its own suite; this guards the empty board
  # and the counting.
  test "survives an empty board and reports zero warmed" do
    result = WarmSituationLayersJob.perform_now

    assert_equal 0, result[:records_fetched]
    assert_equal 0, result[:records_stored]
  end

  test "the situations build enqueues the warm" do
    HazardOccurrenceLinkService.stub(:sync_recent, nil) do
      SituationBuilder.stub(:call, nil) do
        assert_enqueued_with(job: WarmSituationLayersJob) { BuildSituationsJob.perform_now }
      end
    end
  end
end
