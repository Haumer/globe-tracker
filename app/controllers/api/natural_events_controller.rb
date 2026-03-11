module Api
  class NaturalEventsController < ApplicationController
    include TimelineRecorder
    skip_before_action :authenticate_user!

    def index
      require "net/http"
      require "json"

      # Skip external API fetch when querying historical data (timeline mode)
      unless params[:from].present? && params[:to].present?
        uri = URI("https://eonet.gsfc.nasa.gov/api/v3/events?status=open&limit=100")
        response = Net::HTTP.get_response(uri)

        if response.is_a?(Net::HTTPSuccess)
          data = JSON.parse(response.body)
          events = data["events"] || []
          now = Time.current

          records = events.filter_map do |ev|
            geo = ev["geometry"]&.first
            cat = ev["categories"]&.first || {}
            next if geo.nil? || geo["coordinates"].nil?

            lat = geo["coordinates"][1]&.to_f
            lng = geo["coordinates"][0]&.to_f
            next if lat.nil? || lng.nil?

            {
              external_id: ev["id"],
              title: ev["title"],
              category_id: cat["id"] || "unknown",
              category_title: cat["title"] || "Unknown",
              latitude: lat,
              longitude: lng,
              event_date: geo["date"] ? Time.parse(geo["date"]) : nil,
              magnitude_value: geo["magnitudeValue"]&.to_f,
              magnitude_unit: geo["magnitudeUnit"],
              link: ev["link"].is_a?(String) ? ev["link"] : nil,
              sources: (ev["sources"] || []).to_json,
              geometry_points: (ev["geometry"] || []).to_json,
              fetched_at: now,
              created_at: now,
              updated_at: now,
            }
          end

          if records.any?
            NaturalEvent.upsert_all(records, unique_by: :external_id)
            record_timeline_events(
              event_type: "natural_event",
              model_class: NaturalEvent,
              unique_key: :external_id,
              unique_values: records.map { |r| r[:external_id] },
              time_column: :event_date
            )
          end
        end
      end

      events = if params[:from].present? && params[:to].present?
                 from = Time.parse(params[:from]) rescue 24.hours.ago
                 to = Time.parse(params[:to]) rescue Time.current
                 NaturalEvent.in_range(from, to)
               else
                 NaturalEvent.recent
               end.order(event_date: :desc).limit(200)
      render json: events.map { |ev|
        {
          id: ev.external_id,
          title: ev.title,
          categoryId: ev.category_id,
          categoryTitle: ev.category_title,
          lat: ev.latitude,
          lng: ev.longitude,
          date: ev.event_date&.iso8601,
          magnitudeValue: ev.magnitude_value,
          magnitudeUnit: ev.magnitude_unit,
          link: ev.link,
          sources: ev.sources.is_a?(String) ? JSON.parse(ev.sources) : (ev.sources || []),
          geometryPoints: ev.geometry_points.is_a?(String) ? JSON.parse(ev.geometry_points) : (ev.geometry_points || []),
        }
      }
    end
  end
end
