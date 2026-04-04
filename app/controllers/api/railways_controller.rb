module Api
  class RailwaysController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      return render json: [] unless LayerAvailability.enabled?(:railways)

      # Viewport-filtered query
      scope = Railway.all

      if params[:bbox].present?
        parts = params[:bbox].split(",").map(&:to_f)
        if parts.size == 4
          south, west, north, east = parts
          scope = scope.where("max_lat >= ? AND min_lat <= ? AND max_lng >= ? AND min_lng <= ?",
                              south, north, west, east)
        end
      end

      # Cap at 3000 segments per request
      railways = scope.limit(3000)

      render json: railways.map { |r|
        [r.id, r.category, r.electrified, r.continent, r.coordinates]
      }
    end
  end
end
