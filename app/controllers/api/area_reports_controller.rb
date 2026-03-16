module Api
  class AreaReportsController < ApplicationController
    skip_before_action :authenticate_user!

    def show
      bounds = parse_bounds
      cache_key = "area_report:#{bounds&.values&.map { |v| v.to_f.round(1) }&.join(',')}"
      report = Rails.cache.fetch(cache_key, expires_in: 2.minutes) do
        AreaReport.generate(bounds)
      end
      expires_in 2.minutes, public: true
      render json: report
    end
  end
end
