class PollOpenskyJob < ApplicationJob
  queue_as :default
  tracks_polling source: "opensky", poll_type: "flights"

  def perform
    OpenskyService.fetch_flights(bounds: {}).size
  end
end
