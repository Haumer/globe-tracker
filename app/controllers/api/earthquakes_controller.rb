module Api
  class EarthquakesController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      unless params[:from].present? && params[:to].present?
        enqueue_background_refresh(RefreshEarthquakesJob, key: "earthquakes", debounce: 30.seconds) if EarthquakeRefreshService.stale?
      end

      quakes = if params[:from].present? && params[:to].present?
                 from = Time.parse(params[:from]) rescue 24.hours.ago
                 to = Time.parse(params[:to]) rescue Time.current
                 Earthquake.in_range(from, to)
               else
                 Earthquake.recent
               end.order(event_time: :desc).limit(500)
      render json: quakes.map { |eq|
        {
          id: eq.external_id,
          title: eq.title,
          mag: eq.magnitude,
          magType: eq.magnitude_type,
          lat: eq.latitude,
          lng: eq.longitude,
          depth: eq.depth,
          time: eq.event_time&.to_i&.*(1000),
          url: eq.url,
          tsunami: eq.tsunami,
          alert: eq.alert,
        }
      }
    end
  end
end
