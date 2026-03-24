class PollAdsbRegionJob < ApplicationJob
  queue_as :default
  tracks_polling source: ->(_job, args) { "adsb-#{args.first}" }, poll_type: "flights"

  def perform(region_name, lat, lon)
    bounds = {
      lamin: lat - 20, lamax: lat + 20,
      lomin: lon - 25, lomax: lon + 25,
    }
    AdsbService.fetch_flights(bounds: bounds).size
  end
end
