module Api
  class InternetOutagesController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      outages = []

      unless params[:from].present? && params[:to].present?
        enqueue_background_refresh(RefreshInternetOutagesJob, key: "internet-outages", debounce: 30.seconds) if InternetOutageRefreshService.stale?
        outages = InternetOutageRefreshService.cached_summary
      end

      recent_events = if params[:from].present? && params[:to].present?
                        from = Time.parse(params[:from]) rescue 24.hours.ago
                        to = Time.parse(params[:to]) rescue Time.current
                        InternetOutage.in_range(from, to)
                      else
                        InternetOutage.recent
                      end.order(started_at: :desc).limit(100)
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
