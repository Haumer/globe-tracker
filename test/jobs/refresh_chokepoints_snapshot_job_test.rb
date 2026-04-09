require "test_helper"

class RefreshChokepointsSnapshotJobTest < ActiveSupport::TestCase
  test "is assigned to the default queue" do
    assert_equal "default", RefreshChokepointsSnapshotJob.new.queue_name
  end

  test "tracks polling with source derived-chokepoints and poll_type derived_layer" do
    assert_equal "derived-chokepoints", RefreshChokepointsSnapshotJob.polling_source_resolver
    assert_equal "derived_layer", RefreshChokepointsSnapshotJob.polling_type_resolver
  end

  test "calls ChokepointSnapshotService.refresh and returns counts" do
    snapshot = OpenStruct.new(payload: { "chokepoints" => [1, 2, 3] })

    ChokepointSnapshotService.stub(:refresh, snapshot) do
      result = RefreshChokepointsSnapshotJob.perform_now
      assert_equal({ records_fetched: 3, records_stored: 3 }, result)
    end
  end
end
