require "test_helper"

class RefreshInsightsSnapshotJobTest < ActiveSupport::TestCase
  test "is assigned to the default queue" do
    assert_equal "default", RefreshInsightsSnapshotJob.new.queue_name
  end

  test "tracks polling with source derived-insights and poll_type derived_layer" do
    assert_equal "derived-insights", RefreshInsightsSnapshotJob.polling_source_resolver
    assert_equal "derived_layer", RefreshInsightsSnapshotJob.polling_type_resolver
  end

  test "calls InsightSnapshotService.refresh and returns counts" do
    snapshot = OpenStruct.new(payload: { "insights" => %w[a b c d] })

    InsightSnapshotService.stub(:refresh, snapshot) do
      result = RefreshInsightsSnapshotJob.perform_now
      assert_equal({ records_fetched: 4, records_stored: 4 }, result)
    end
  end
end
