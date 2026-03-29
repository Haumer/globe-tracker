class PersistYahooMarketSignalsJob < ApplicationJob
  queue_as :background
  tracks_polling source: "yahoo-finance", poll_type: "market_signals"

  def perform
    result = YahooMarketSignalService.persist_significant_moves
    {
      records_fetched: result.fetch(:fetched, 0),
      records_stored: result.fetch(:stored, 0),
    }
  end
end
