require "test_helper"

class EnrichNewsJobTest < ActiveSupport::TestCase
  test "is assigned to the default queue" do
    assert_equal "default", EnrichNewsJob.new.queue_name
  end

  test "calls NewsEnrichmentService.enrich_recent with limit 100" do
    called = false
    mock = ->(**kwargs) { called = true; assert_equal 100, kwargs[:limit]; [] }

    NewsEnrichmentService.stub(:enrich_recent, mock) do
      EnrichNewsJob.perform_now
    end

    assert called, "Expected NewsEnrichmentService.enrich_recent to be called"
  end
end
