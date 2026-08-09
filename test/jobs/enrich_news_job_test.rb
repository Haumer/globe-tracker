require "test_helper"

class EnrichNewsJobTest < ActiveSupport::TestCase
  test "is assigned to the default queue" do
    assert_equal "default", EnrichNewsJob.new.queue_name
  end

  test "enriches enough per run to stay ahead of ingest" do
    # Ingest runs ~1,300-1,800/hour; at 12 runs/hour this has to clear that
    # rate or the excess reaches the globe on the publisher-domain fallback.
    assert_operator EnrichNewsJob::BATCH_LIMIT * 12, :>=, 1_800
  end

  test "calls NewsEnrichmentService.enrich_recent with the batch limit" do
    called = false
    mock = ->(**kwargs) { called = true; assert_equal EnrichNewsJob::BATCH_LIMIT, kwargs[:limit]; [] }

    NewsEnrichmentService.stub(:enrich_recent, mock) do
      EnrichNewsJob.perform_now
    end

    assert called, "Expected NewsEnrichmentService.enrich_recent to be called"
  end
end
