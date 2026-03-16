module Api
  class ConflictEventsController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      # UCDP data is historical (annual releases) — default to all events, not just "recent"
      range = parse_time_range
      scope = range ? ConflictEvent.in_range(*range) : ConflictEvent.all
      bounds = parse_bounds
      scope = scope.within_bounds(bounds) if bounds.present?

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
  end
end
