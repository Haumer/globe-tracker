class RefreshAirportsJob < ApplicationJob
  queue_as :default

  def perform
    OurAirportsService.refresh_if_stale
  end
end
