module Api
  class ConflictEventsController < ApplicationController
    include TimelineRecorder
    skip_before_action :authenticate_user!

    def index
      unless params[:from].present? && params[:to].present?
        ConflictEventService.fetch_recent if ConflictEvent.count == 0
      end

      scope = if params[:from].present? && params[:to].present?
        ConflictEvent.in_range(params[:from], params[:to])
      else
        ConflictEvent.recent
      end

      scope = scope.within_bounds(bounds_params) if bounds_params

      events = scope.order(date_start: :desc).limit(2000)

      render json: events.map { |e|
        {
          id: e.id,
          lat: e.latitude,
          lng: e.longitude,
          conflict: e.conflict_name,
          side_a: e.side_a,
          side_b: e.side_b,
          country: e.country,
          region: e.region,
          location: e.where_description,
          date_start: e.date_start&.iso8601,
          date_end: e.date_end&.iso8601,
          deaths: e.best_estimate,
          deaths_civilians: e.deaths_civilians,
          type: e.type_of_violence,
          type_label: e.violence_label,
          headline: e.source_headline,
        }
      }
    end

    private

    def bounds_params
      if params[:lamin].present?
        { lamin: params[:lamin].to_f, lamax: params[:lamax].to_f,
          lomin: params[:lomin].to_f, lomax: params[:lomax].to_f }
      end
    end
  end
end
