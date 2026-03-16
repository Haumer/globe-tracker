class PollAdsbRegionJob < ApplicationJob
  queue_as :default

  def perform(region_name, lat, lon)
    bounds = {
      lamin: lat - 20, lamax: lat + 20,
      lomin: lon - 25, lomax: lon + 25,
    }
    AdsbService.fetch_flights(bounds: bounds)
  end
end
