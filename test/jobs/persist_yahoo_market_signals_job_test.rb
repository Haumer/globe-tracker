require "test_helper"

class PersistYahooMarketSignalsJobTest < ActiveSupport::TestCase
  test "is assigned to the background queue" do
    assert_equal "background", PersistYahooMarketSignalsJob.new.queue_name
  end

  test "tracks polling with source yahoo-finance and poll_type market_signals" do
    assert_equal "yahoo-finance", PersistYahooMarketSignalsJob.polling_source_resolver
    assert_equal "market_signals", PersistYahooMarketSignalsJob.polling_type_resolver
  end

  test "calls YahooMarketSignalService.persist_significant_moves and returns counts" do
    service_result = { fetched: 10, stored: 3 }

    YahooMarketSignalService.stub(:persist_significant_moves, service_result) do
      result = PersistYahooMarketSignalsJob.perform_now
      assert_equal({ records_fetched: 10, records_stored: 3 }, result)
    end
  end
end
