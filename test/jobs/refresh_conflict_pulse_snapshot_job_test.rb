require "test_helper"

class RefreshConflictPulseSnapshotJobTest < ActiveSupport::TestCase
  test "is assigned to the default queue" do
    assert_equal "default", RefreshConflictPulseSnapshotJob.new.queue_name
  end

  test "tracks polling with source derived-conflict-pulse and poll_type derived_layer" do
    assert_equal "derived-conflict-pulse", RefreshConflictPulseSnapshotJob.polling_source_resolver
    assert_equal "derived_layer", RefreshConflictPulseSnapshotJob.polling_type_resolver
  end

  test "calls ConflictPulseSnapshotService.refresh and returns counts" do
    snapshot = OpenStruct.new(payload: { "zones" => [1, 2] })

    ConflictPulseSnapshotService.stub(:refresh, snapshot) do
      result = RefreshConflictPulseSnapshotJob.perform_now
      assert_equal({ records_fetched: 2, records_stored: 2 }, result)
    end
  end
end
