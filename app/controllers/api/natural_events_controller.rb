module Api
  class NaturalEventsController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      unless params[:from].present? && params[:to].present?
        enqueue_background_refresh(RefreshNaturalEventsJob, key: "natural-events", debounce: 30.seconds) if NaturalEventRefreshService.stale?
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
