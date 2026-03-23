module Api
  class StrikesController < ApplicationController
    skip_before_action :authenticate_user!

    # Reuse conflict country bounds from fire hotspots controller
    CONFLICT_COUNTRIES = Api::FireHotspotsController::CONFLICT_COUNTRIES

    def index
      # Query only high-confidence hotspots in conflict zones
      hotspots = FireHotspot.recent
        .where(confidence: %w[high h])
        .where("frp > 20 OR brightness > 360 OR daynight = 'N'")
        .order(acq_datetime: :desc)

      # Filter to conflict zone bounds in Ruby (faster than complex SQL OR chains)
      strikes = hotspots.select do |h|
        CONFLICT_COUNTRIES.any? { |_, b| b[:lat].cover?(h.latitude) && b[:lng].cover?(h.longitude) }
      end

      expires_in 5.minutes, public: true

      render json: strikes.map { |h|
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
