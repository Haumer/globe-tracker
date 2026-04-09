require "test_helper"

class RefreshSectorInputsJobTest < ActiveSupport::TestCase
  test "is assigned to the background queue" do
    assert_equal "background", RefreshSectorInputsJob.new.queue_name
  end

  test "tracks polling with source sector-inputs and poll_type sector_inputs" do
    assert_equal "sector-inputs", RefreshSectorInputsJob.polling_source_resolver
    assert_equal "sector_inputs", RefreshSectorInputsJob.polling_type_resolver
  end

  test "calls SectorInputRefreshService.refresh_if_stale" do
    called = false
    SectorInputRefreshService.stub(:refresh_if_stale, -> { called = true; 7 }) do
      RefreshSectorInputsJob.perform_now
    end
    assert called
  end
end
