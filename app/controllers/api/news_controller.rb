module Api
  class NewsController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      priority_sql = <<~SQL.squish
        ABS(tone) * EXP(-0.1 * LEAST(EXTRACT(EPOCH FROM (NOW() - COALESCE(published_at, fetched_at))) / 3600.0, 200))
      SQL

      events = time_scoped(NewsEvent)
                 .includes(:news_source, :news_article)
                 .select("news_events.*, (#{priority_sql}) AS priority")
                 .order(Arel.sql("(#{priority_sql}) DESC NULLS LAST"))
                 .limit(10_000)
                 .to_a
      claim_summaries = claim_summaries_for(events)

      expires_in 2.minutes, public: true

      if params[:clustered] == "true"
        render json: clustered_response(events, claim_summaries)
      else
        render json: events.map { |ev| serialize_event(ev, claim_summaries[ev.news_article_id]) }
      end
    end

    private

    def serialize_event(ev, claim_summary = nil)
      publisher_name = ev.news_source&.name || ev.news_article&.publisher_name

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
        publisher: publisher_name,
        content_scope: ev.content_scope,
        claim_event_family: claim_summary&.dig(:event_family),
        claim_event_type: claim_summary&.dig(:event_type),
        claim_confidence: claim_summary&.dig(:confidence),
        actors: claim_summary&.dig(:actors) || [],
        time: ev.published_at&.iso8601,
        priority: ev[:priority]&.to_f&.round(3),
        cluster_id: ev.story_cluster_id,
      }
    end

    def clustered_response(events, claim_summaries)
      grouped = events.group_by(&:story_cluster_id)

      grouped.map do |cluster_id, group|
        # For multi-article clusters, pick the best lead (highest credibility/priority)
        lead = group.size > 1 ? group.max_by { |a| a[:priority]&.to_f || 0 } : group.first
        entry = serialize_event(lead, claim_summaries[lead.news_article_id])
        if cluster_id.present? && group.size > 1
          # Filter out junk single-source clusters (e.g., GDELT location-only dupes)
          unique_sources = group.filter_map { |article| article.news_source&.name || article.source }
            .uniq
            .reject(&:blank?)
          if unique_sources.size > 1
            entry[:source_count] = group.size
            entry[:sources] = unique_sources
          end
        end
        entry
      end
    end

    def claim_summaries_for(events)
      article_ids = events.filter_map(&:news_article_id).uniq
      return {} if article_ids.empty?

      NewsClaim.where(news_article_id: article_ids, primary: true)
        .includes(news_claim_actors: :news_actor)
        .each_with_object({}) do |claim, mapping|
          mapping[claim.news_article_id] = {
            event_family: claim.event_family,
            event_type: claim.event_type,
            confidence: claim.confidence&.round(2),
            actors: claim.news_claim_actors.sort_by(&:position).map do |claim_actor|
              actor = claim_actor.news_actor
              next unless actor

              {
                name: actor.name,
                role: claim_actor.role,
                actor_type: actor.actor_type,
              }
            end.compact,
          }
        end
    end
  end
end
