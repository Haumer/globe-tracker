module Api
  class WeatherAlertsController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      alerts = WeatherAlert.active
      bounds = parse_bounds
      alerts = alerts.within_bounds(bounds) if bounds.present?

      render json: {
        alerts: alerts.map { |a|
          {
            event: a.event,
            severity: a.severity,
            urgency: a.urgency,
            certainty: a.certainty,
            headline: a.headline,
            description: a.description,
            areas: a.areas,
            onset: a.onset&.iso8601,
            expires: a.expires&.iso8601,
            sender: a.sender,
            lat: a.latitude,
            lng: a.longitude,
          }
        },
        fetched_at: WeatherAlert.maximum(:fetched_at)&.iso8601,
        count: alerts.size,
      }
    end
  end
end
