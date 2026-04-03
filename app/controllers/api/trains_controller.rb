module Api
  class TrainsController < ApplicationController
    skip_before_action :authenticate_user!

    LIST_COLUMNS = %i[
      external_id name category category_long operator_name flag
      latitude longitude direction progress fetched_at expires_at
      matched_railway_id snapped_latitude snapped_longitude
      snap_distance_m snap_confidence
    ].freeze

    def index
      return render json: [] unless LayerAvailability.enabled?(:trains)

      trains = TrainObservation.current.select(*LIST_COLUMNS)
      trains = trains.within_bounds(parse_bbox(params[:bbox])) if params[:bbox].present?

      expires_in 10.seconds, public: true

      render json: trains.map { |train|
        {
          id: train.external_id,
          name: train.name,
          category: train.category,
          categoryLong: train.category_long,
          operator: train.operator_name,
          flag: train.flag,
          lat: train.latitude,
          lng: train.longitude,
          direction: train.direction,
          progress: train.progress,
          matchedRailwayId: train.matched_railway_id,
          snappedLat: train.snapped_latitude,
          snappedLng: train.snapped_longitude,
          snapDistanceM: train.snap_distance_m,
          snapConfidence: train.snap_confidence,
          fetchedAt: train.fetched_at&.iso8601,
          expiresAt: train.expires_at&.iso8601,
        }
      }
    end

    private

    def parse_bbox(value)
      south, west, north, east = value.to_s.split(",").map(&:to_f)
      return {} unless value.present? && value.to_s.split(",").size == 4

      { lamin: south, lamax: north, lomin: west, lomax: east }
    end
  end
end
