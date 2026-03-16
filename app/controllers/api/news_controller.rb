module Api
  class NewsController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      priority_sql = <<~SQL.squish
        ABS(tone) * EXP(-0.1 * LEAST(EXTRACT(EPOCH FROM (NOW() - COALESCE(published_at, fetched_at))) / 3600.0, 200))
      SQL

      events = time_scoped(NewsEvent)
                 .select("news_events.*, (#{priority_sql}) AS priority")
                 .order(Arel.sql("(#{priority_sql}) DESC NULLS LAST"))
                 .limit(10_000)

      expires_in 2.minutes, public: true

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
        # For multi-article clusters, pick the best lead (highest credibility/priority)
        lead = group.size > 1 ? group.max_by { |a| a[:priority]&.to_f || 0 } : group.first
        entry = serialize_event(lead)
        if cluster_id.present? && group.size > 1
          # Filter out junk single-source clusters (e.g., GDELT location-only dupes)
          unique_sources = group.map(&:source).compact.uniq.reject(&:blank?)
          if unique_sources.size > 1
            entry[:source_count] = group.size
            entry[:sources] = unique_sources.map { |s| s.split("/").first.strip }
          end
        end
        entry
      end
    end
  end
end
