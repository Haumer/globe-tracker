module Api
  class FireHotspotsController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      hotspots = FireHotspot.recent.order(acq_datetime: :desc).limit(5000)

      render json: hotspots.map { |h|
        [
          h.external_id,
          h.latitude,
          h.longitude,
          h.brightness,
          h.confidence,
          h.satellite,
          h.instrument,
          h.frp,
          h.daynight,
          h.acq_datetime&.to_i&.*(1000),
        ]
      }
    end
  end
end
