class PollOpenskyJob < ApplicationJob
  queue_as :fast_live
  tracks_polling source: "opensky", poll_type: "flights"

  def perform
    OpenskyService.fetch_flights(bounds: {}).size
  end
end
