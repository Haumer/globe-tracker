class PollAdsbMilitaryJob < ApplicationJob
  queue_as :fast_live
  tracks_polling source: "adsb-military", poll_type: "flights"

  def perform
    AdsbService.fetch_military.size
  end
end
