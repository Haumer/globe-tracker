require "test_helper"

class RefreshSubmarineCablesJobTest < ActiveSupport::TestCase
  test "is assigned to the background queue" do
    assert_equal "background", RefreshSubmarineCablesJob.new.queue_name
  end

  test "tracks polling with source submarine-cables and poll_type submarine_cables" do
    assert_equal "submarine-cables", RefreshSubmarineCablesJob.polling_source_resolver
    assert_equal "submarine_cables", RefreshSubmarineCablesJob.polling_type_resolver
  end

  test "calls SubmarineCableRefreshService.refresh_if_stale" do
    called = false
    SubmarineCableRefreshService.stub(:refresh_if_stale, -> { called = true; 20 }) do
      RefreshSubmarineCablesJob.perform_now
    end
    assert called
  end
end
