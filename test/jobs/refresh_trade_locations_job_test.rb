require "test_helper"

class RefreshTradeLocationsJobTest < ActiveSupport::TestCase
  test "is assigned to the background queue" do
    assert_equal "background", RefreshTradeLocationsJob.new.queue_name
  end

  test "tracks polling with source trade-locations and poll_type trade_locations" do
    assert_equal "trade-locations", RefreshTradeLocationsJob.polling_source_resolver
    assert_equal "trade_locations", RefreshTradeLocationsJob.polling_type_resolver
  end

  test "calls TradeLocationRefreshService.refresh_if_stale" do
    called = false
    TradeLocationRefreshService.stub(:refresh_if_stale, -> { called = true; 8 }) do
      RefreshTradeLocationsJob.perform_now
    end
    assert called
  end
end
