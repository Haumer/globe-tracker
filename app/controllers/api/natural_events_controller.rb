module Api
  class NaturalEventsController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      events = time_scoped(NaturalEvent).order(event_date: :desc).limit(200)
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
          sources: parse_json_field(ev.sources),
          geometryPoints: parse_json_field(ev.geometry_points),
        }
      }
    end
  end
end
