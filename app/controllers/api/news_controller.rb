module Api
  class NewsController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      unless parse_time_range
        enqueue_background_refresh(RefreshNewsJob, key: "news", debounce: 1.minute) if NewsRefreshService.stale?
      end

      priority_sql = <<~SQL.squish
        ABS(tone) * EXP(-0.1 * LEAST(EXTRACT(EPOCH FROM (NOW() - COALESCE(published_at, fetched_at))) / 3600.0, 200))
      SQL

      events = time_scoped(NewsEvent)
                 .select("news_events.*, (#{priority_sql}) AS priority")
                 .order(Arel.sql("(#{priority_sql}) DESC NULLS LAST"))

      if params[:clustered] == "true"
        render json: clustered_response(events)
      else
        render json: events.map { |ev| serialize_event(ev) }
      end
    end

    private

    def serialize_event(ev)
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
        priority: ev[:priority]&.to_f&.round(3),
        cluster_id: ev.story_cluster_id,
      }
    end

    def clustered_response(events)
      grouped = events.group_by(&:story_cluster_id)

      grouped.map do |cluster_id, group|
        lead = group.first
        entry = serialize_event(lead)
        if cluster_id.present? && group.size > 1
          entry[:source_count] = group.size
          entry[:sources] = group.map(&:source).uniq
        end
        entry
      end
    end
  end
end
