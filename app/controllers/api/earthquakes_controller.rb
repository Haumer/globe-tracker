module Api
  class EarthquakesController < ApplicationController
    include TimelineRecorder
    skip_before_action :authenticate_user!

    def index
      require "net/http"
      require "json"

      # Skip external API fetch when querying historical data (timeline mode)
      unless params[:from].present? && params[:to].present?
        # Fetch from USGS and persist
        uri = URI("https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/2.5_day.geojson")
        response = Net::HTTP.get_response(uri)

        if response.is_a?(Net::HTTPSuccess)
          data = JSON.parse(response.body)
          features = data["features"] || []
          now = Time.current

          records = features.filter_map do |f|
            props = f["properties"] || {}
            coords = f.dig("geometry", "coordinates")
            next if coords.nil? || coords.length < 3

            {
              external_id: f["id"],
              title: props["place"] || "Unknown",
              magnitude: props["mag"],
              magnitude_type: props["magType"] || "",
              latitude: coords[1].to_f,
              longitude: coords[0].to_f,
              depth: coords[2].to_f,
              event_time: props["time"] ? Time.at(props["time"] / 1000.0) : nil,
              url: props["url"],
              tsunami: props["tsunami"] == 1,
              alert: props["alert"],
              fetched_at: now,
              created_at: now,
              updated_at: now,
            }
          end

          if records.any?
            Earthquake.upsert_all(records, unique_by: :external_id)
            record_timeline_events(
              event_type: "earthquake",
              model_class: Earthquake,
              unique_key: :external_id,
              unique_values: records.map { |r| r[:external_id] },
              time_column: :event_time
            )
          end
        end
      end

      # Return earthquakes — support timeline filtering
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
