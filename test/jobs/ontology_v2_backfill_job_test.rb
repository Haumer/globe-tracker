require "test_helper"

class OntologyV2BackfillJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "is assigned to the background queue" do
    assert_equal "background", OntologyV2BackfillJob.new.queue_name
  end

  test "polling source resolves from stage keyword argument" do
    resolver = OntologyV2BackfillJob.polling_source_resolver

    assert_equal "ontology-v2-backfill:event_graph", resolver.call(nil, [{ stage: "event_graph" }])
  end

  test "enqueues next batch when current stage is incomplete" do
    result = {
      stage: "asset_airports",
      next_cursor: 42,
      complete: false,
      records_fetched: 1,
      records_stored: 1,
    }

    OntologyV2BackfillService.stub(:run, ->(**_opts) { result }) do
      assert_enqueued_with(job: OntologyV2BackfillJob) do
        OntologyV2BackfillJob.perform_now(stage: "asset_airports", batch_size: 1)
      end
    end
  end

  test "enqueues next stage when current stage is complete" do
    result = {
      stage: "asset_airports",
      next_stage: "asset_military_bases",
      complete: true,
      records_fetched: 1,
      records_stored: 1,
    }

    OntologyV2BackfillService.stub(:run, ->(**_opts) { result }) do
      assert_enqueued_with(job: OntologyV2BackfillJob) do
        OntologyV2BackfillJob.perform_now(stage: "asset_airports", batch_size: 1)
      end
    end
  end
end
