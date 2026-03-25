class RefreshAirportsJob < ApplicationJob
  queue_as :background
  tracks_polling source: "ourairports", poll_type: "airports"

  def perform
    OurAirportsService.refresh_if_stale
  end
end
