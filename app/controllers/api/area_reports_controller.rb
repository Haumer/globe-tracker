module Api
  class AreaReportsController < ApplicationController
    skip_before_action :authenticate_user!

    def show
      bounds = parse_bounds
      unless bounds.key?(:lamin) && bounds.key?(:lamax) && bounds.key?(:lomin) && bounds.key?(:lomax)
        return render json: { error: "Incomplete bounding box — lamin, lamax, lomin, lomax are all required" }, status: :unprocessable_entity
      end

      cache_key = "area_report:#{bounds.values.map { |v| v.to_f.round(1) }.join(',')}"
      report = Rails.cache.fetch(cache_key, expires_in: 2.minutes) do
        AreaReport.generate(bounds)
      end
      expires_in 2.minutes, public: true
      render json: report
    end
  end
end
