module Api
  class InternetOutagesController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      outages = []

      unless parse_time_range
        enqueue_background_refresh(RefreshInternetOutagesJob, key: "internet-outages", debounce: 30.seconds) if InternetOutageRefreshService.stale?
        outages = InternetOutageRefreshService.cached_summary
      end

      recent_events = time_scoped(InternetOutage).order(started_at: :desc).limit(100)
      render json: {
        summary: outages.sort_by { |o| -o[:score] }.first(50),
        events: recent_events.map { |ev|
          {
            id: ev.external_id,
            code: ev.entity_code,
            name: ev.entity_name,
            datasource: ev.datasource,
            score: ev.score,
            level: ev.level,
            from: ev.started_at&.to_i,
            until: ev.ended_at&.to_i,
          }
        },
      }
    end
  end
end
