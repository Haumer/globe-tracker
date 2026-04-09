require "test_helper"

class RefreshAreaReportSnapshotJobTest < ActiveSupport::TestCase
  test "is assigned to the default queue" do
    assert_equal "default", RefreshAreaReportSnapshotJob.new.queue_name
  end

  test "tracks polling with source derived-area-report and poll_type derived_layer" do
    assert_equal "derived-area-report", RefreshAreaReportSnapshotJob.polling_source_resolver
    assert_equal "derived_layer", RefreshAreaReportSnapshotJob.polling_type_resolver
  end

  test "calls AreaReportSnapshotService.refresh with bounds and returns counts" do
    bounds = { "north" => 50.0, "south" => 40.0, "east" => 20.0, "west" => 10.0 }
    payload = { "section_a" => {}, "section_b" => {} }
    snapshot = OpenStruct.new(payload: payload)

    called_with = nil
    mock = ->(b) { called_with = b; snapshot }

    AreaReportSnapshotService.stub(:refresh, mock) do
      result = RefreshAreaReportSnapshotJob.perform_now(bounds)
      assert_equal({ records_fetched: 2, records_stored: 2 }, result)
    end

    assert_equal :north, called_with.keys.first
  end
end
