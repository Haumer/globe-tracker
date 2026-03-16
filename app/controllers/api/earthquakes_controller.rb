module Api
  class EarthquakesController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      expires_in 1.minute, public: true

      quakes = time_scoped(Earthquake).order(event_time: :desc).limit(500)
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
