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
      origin_source_name = ev.news_article&.origin_source_name || claim_summary&.dig(:origin_source_name)

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
        origin_source: origin_source_name,
        origin_source_kind: ev.news_article&.origin_source_kind || claim_summary&.dig(:origin_source_kind),
        content_scope: ev.content_scope,
        claim_event_family: claim_summary&.dig(:event_family),
        claim_event_type: claim_summary&.dig(:event_type),
        claim_confidence: claim_summary&.dig(:confidence),
        claim_verification_status: claim_summary&.dig(:verification_status),
        claim_source_reliability: claim_summary&.dig(:source_reliability),
        claim_geo_precision: claim_summary&.dig(:geo_precision),
        claim_geo_confidence: claim_summary&.dig(:geo_confidence),
        actors: claim_summary&.dig(:actors) || [],
        time: ev.published_at&.iso8601,
        priority: ev[:priority]&.to_f&.round(3),
        cluster_id: ev.story_cluster_id,
      }
    end

    def clustered_response(events, claim_summaries)
      cluster_keys = events.filter_map(&:story_cluster_id).uniq
      clusters_by_key = NewsStoryCluster.where(cluster_key: cluster_keys).index_by(&:cluster_key)
      grouped = events.group_by { |event| event.story_cluster_id.presence || "event:#{event.id}" }

      grouped.map do |_grouping_key, group|
        # For multi-article clusters, pick the best lead (highest credibility/priority)
        lead = group.size > 1 ? group.max_by { |a| a[:priority]&.to_f || 0 } : group.first
        entry = serialize_event(lead, claim_summaries[lead.news_article_id])
        cluster = lead.story_cluster_id.present? ? clusters_by_key[lead.story_cluster_id] : nil
        if cluster
          entry[:cluster_id] = cluster.cluster_key
          entry[:cluster_confidence] = cluster.cluster_confidence
          entry[:verification_status] = cluster.verification_status
          entry[:cluster_source_reliability] = cluster.source_reliability
          entry[:cluster_geo_precision] = cluster.geo_precision
          entry[:cluster_geo_confidence] = cluster.geo_confidence
          entry[:article_count] = cluster.article_count
          entry[:source_count] = cluster.source_count
        end
        if lead.story_cluster_id.present? && group.size > 1
          # Filter out junk single-source clusters (e.g., GDELT location-only dupes)
          unique_sources = group.filter_map { |article| article.news_source&.name || article.source }
            .uniq
            .reject(&:blank?)
          if unique_sources.size > 1
            entry[:source_count] = [ entry[:source_count].to_i, group.size ].max
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
            verification_status: claim.verification_status,
            source_reliability: claim.source_reliability&.round(2),
            geo_precision: claim.geo_precision,
            geo_confidence: claim.geo_confidence&.round(2),
            origin_source_name: claim.provenance["origin_source_name"],
            origin_source_kind: claim.provenance["origin_source_kind"],
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
