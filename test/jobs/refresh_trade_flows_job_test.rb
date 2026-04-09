require "test_helper"

class RefreshTradeFlowsJobTest < ActiveSupport::TestCase
  test "is assigned to the background queue" do
    assert_equal "background", RefreshTradeFlowsJob.new.queue_name
  end

  test "tracks polling with source strategic-trade-flows and poll_type trade_flows" do
    assert_equal "strategic-trade-flows", RefreshTradeFlowsJob.polling_source_resolver
    assert_equal "trade_flows", RefreshTradeFlowsJob.polling_type_resolver
  end

  test "calls TradeFlowRefreshService.refresh_if_stale" do
    called = false
    TradeFlowRefreshService.stub(:refresh_if_stale, -> { called = true; 12 }) do
      RefreshTradeFlowsJob.perform_now
    end
    assert called
  end
end
