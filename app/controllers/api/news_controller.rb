module Api
  class NewsController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      unless parse_time_range
        enqueue_background_refresh(RefreshNewsJob, key: "news", debounce: 1.minute) if NewsRefreshService.stale?
      end

      events = time_scoped(NewsEvent).order(Arel.sql("ABS(tone) DESC"))
      render json: events.map { |ev|
        {
          lat: ev.latitude,
          lng: ev.longitude,
          name: ev.name,
          title: ev.title,
          url: ev.url,
          tone: ev.tone,
          level: ev.level,
          category: ev.category,
          threat: ev.threat_level,
          credibility: ev.credibility,
          themes: parse_json_field(ev.themes),
          source: ev.source,
          time: ev.published_at&.iso8601,
        }
      }
    end
  end
end
