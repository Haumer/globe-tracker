module Api
  class NewsController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      unless params[:from].present? && params[:to].present?
        enqueue_background_refresh(RefreshNewsJob, key: "news", debounce: 1.minute) if NewsRefreshService.stale?
      end

      events = if params[:from].present? && params[:to].present?
                 from = Time.parse(params[:from]) rescue 24.hours.ago
                 to = Time.parse(params[:to]) rescue Time.current
                 NewsEvent.in_range(from, to)
               else
                 NewsEvent.recent
               end.order(Arel.sql("ABS(tone) DESC")).limit(500)
      render json: events.map { |ev|
        themes = ev.themes.is_a?(String) ? JSON.parse(ev.themes) : (ev.themes || [])
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
          themes: themes,
          source: ev.source,
          time: ev.published_at&.iso8601,
        }
      }
    end
  end
end
