require "test_helper"

class RefreshMilitaryBasesJobTest < ActiveSupport::TestCase
  test "is assigned to the background queue" do
    assert_equal "background", RefreshMilitaryBasesJob.new.queue_name
  end

  test "tracks polling with source military-bases and poll_type military_bases" do
    assert_equal "military-bases", RefreshMilitaryBasesJob.polling_source_resolver
    assert_equal "military_bases", RefreshMilitaryBasesJob.polling_type_resolver
  end

  test "calls MilitaryBaseRefreshService.refresh_if_stale" do
    called = false
    MilitaryBaseRefreshService.stub(:refresh_if_stale, -> { called = true; 5 }) do
      RefreshMilitaryBasesJob.perform_now
    end
    assert called
  end
end
