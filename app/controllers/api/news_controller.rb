module Api
  class NewsController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      priority_sql = <<~SQL.squish
        ABS(tone) * EXP(-0.1 * LEAST(EXTRACT(EPOCH FROM (NOW() - COALESCE(published_at, fetched_at))) / 3600.0, 200))
      SQL

      # content_scope gated claim extraction and clustering but never the map, so
      # every headline the scope classifier rejected still rendered as a pin --
      # about two thirds of them. NewsScopeClassifier only matches English terms,
      # so the rejected pile is mostly non-English local reporting plus the
      # sports and entertainment it is actually meant to catch.
      #
      # Filtered here rather than at write time on purpose. The classifier is
      # known to be crude, so this stays reversible: news_events keeps the rows
      # and widening the filter is a one-line change, where declining to persist
      # would throw away anything it misjudges.
      #
      # IS DISTINCT FROM, not `where.not`: a NULL scope is unclassified, not out
      # of scope, but `NOT (content_scope = 'out_of_scope')` evaluates to NULL
      # for those rows, so the plain negation drops all 1,885 of them too.
      events = time_scoped(NewsEvent)
                 .where("news_events.content_scope IS DISTINCT FROM ?", "out_of_scope")
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
        # The article's own standfirst. Never used to be serialized at all, which
        # is why a pin with no extracted claim had nothing to show but its
        # publisher: every other line in the detail overlay is built from claim
        # fields, and those exist for a minority of events.
        summary: summary_for(ev),
        url: ev.url,
        tone: ev.tone,
        level: ev.level,
        category: ev.category,
        threat: ev.threat_level,
        credibility: ev.credibility,
        themes: parse_json_field(ev.themes),
        theme_labels: theme_labels(ev),
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

        # How much to trust the dot's position. Populated on every row, unlike
        # claim_geo_precision above which only exists for the ~10% of events with
        # a primary claim. Roughly half of live events are country centroids, and
        # the globe had no way to tell those apart from a real street-level fix.
        geo_precision: ev.geocode_precision,
        geo_confidence: ev.geocode_confidence&.to_f&.round(2),
        geo_basis: ev.geocode_basis,
        geo_country_code: ev.geocode_country_code,
        place_name: located_place_name(ev),
      }
    end

    # Trim the standfirst to something a 320px card can hold. Publishers pad
    # these with boilerplate, so cut on a sentence boundary when there is one
    # close enough rather than always ending mid-clause.
    SUMMARY_LIMIT = 280

    # Feeds routinely put their tag list in the description element, so a tenth
    # of stored summaries are things like "Rusija, Karas Ukrainoje" or a bare
    # "us-iran" slug. Those read as a broken card, so require something with the
    # shape of a sentence and show nothing rather than a keyword salad.
    SUMMARY_MIN_LENGTH = 40
    SUMMARY_MIN_WORDS = 5

    def summary_for(ev)
      # RSS descriptions routinely carry markup -- a whole "<a href=...>Read
      # more</a>" block, image tags, tracking pixels. Measuring length before
      # stripping let those clear the minimum, and the truncation then cut the
      # tag apart and served a literal "<a…" as the standfirst.
      text = strip_markup(ev.news_article&.summary)
      return nil if text.blank?
      return nil if text.length < SUMMARY_MIN_LENGTH
      return nil if text.split(/\s+/).size < SUMMARY_MIN_WORDS
      return nil if text.casecmp?(ev.title.to_s.squish)
      return nil if keyword_list?(text)
      return text if text.length <= SUMMARY_LIMIT

      window = text[0, SUMMARY_LIMIT]
      boundary = window.rindex(/[.!?](\s|\z)/)
      return window[0..boundary] if boundary && boundary > SUMMARY_LIMIT / 2

      "#{window.sub(/\s+\S*\z/, '')}…"
    end

    def strip_markup(value)
      return "" if value.blank?

      # Nokogiri drops the elements and resolves the entities in one pass.
      # strip_tags leaves entities behind (that is how "Colombia&nbsp;&nbsp;CNN"
      # reached the card) and CGI.unescapeHTML only knows the basic five, so
      # &nbsp; survived both. Collapse the resulting NBSPs into real spaces.
      Nokogiri::HTML::DocumentFragment.parse(value.to_s).text
        .gsub(/[\u00a0\u2007\u202f]/, " ")
        .gsub(/\s+/, " ")
        .strip
    end

    # GDELT records arrive with no standfirst and, unless a rule and a known
    # actor both match, no claim either -- so their themes are the only thing
    # the card has left to say. They were serialized raw and never displayed,
    # which is how a pin ended up showing its publisher and nothing else.
    #
    # GDELT's taxonomy is not presentable as-is: codes are SCREAMING_SNAKE with
    # dataset prefixes (EPU_CATS_, WB_695_) and the TAX_* family tags nouns
    # rather than events -- TAX_FNCACT_IMAM says a cleric was mentioned, not
    # what happened.
    THEME_LABELS = {
      "ARMEDCONFLICT" => "Armed conflict",
      "CYBER_ATTACK" => "Cyber attack",
      "ECON_BANKRUPTCY" => "Bankruptcy",
      "ECON_STOCKMARKET" => "Stock market",
      "ENV_EARTHQUAKE" => "Earthquake",
      "ENV_FLOOD" => "Flood",
      "ENV_HURRICANE" => "Hurricane",
      "ENV_VOLCANO" => "Volcano",
      "ENV_WILDFIRE" => "Wildfire",
      "EPU_CATS_NATIONAL_SECURITY" => "National security",
      "GENERAL_GOVERNMENT" => "Government",
      "GENERAL_HEALTH" => "Health",
      "HEALTH_EPIDEMIC" => "Epidemic",
      "HEALTH_PANDEMIC" => "Pandemic",
      "WB_695_POVERTY" => "Poverty",
    }.freeze

    THEME_NOISE = /\A(?:TAX_|SOC_POINTSOF|UNGP_|CRISISLEX_)/
    THEME_STRIP = /\A(?:EPU_CATS_|WB_\d+_|ECON_|ENV_|HEALTH_|GENERAL_)/
    THEME_LIMIT = 3

    def theme_labels(ev)
      Array(parse_json_field(ev.themes)).filter_map do |theme|
        code = theme.to_s.strip.upcase
        next if code.blank? || code.match?(THEME_NOISE)

        THEME_LABELS[code] || code.sub(THEME_STRIP, "").tr("_", " ").downcase.upcase_first.presence
      end.uniq.first(THEME_LIMIT)
    end

    # A comma-separated keyword list is not a standfirst. Feeds emit plenty of
    # them ("North Korea, Russia, Ukraine, conflict, troops"), and they are long
    # enough and wordy enough to clear the length and word-count gates. Prose has
    # long stretches between its commas; a tag list does not.
    def keyword_list?(text)
      segments = text.split(",").map { |segment| segment.split(/\s+/).reject(&:empty?).size }
      return false if segments.size < 3

      (segments.sum.to_f / segments.size) < 3.0
    end

    # geocode_place_name is only a place for the precise tiers. On country-precision
    # rows it is frequently the publisher ("Die Zeit", "NYT World") or a bare
    # two-letter code, so surfacing it there would label a centroid with a masthead.
    LOCATED_PRECISIONS = %w[city place region airport].freeze

    def located_place_name(ev)
      return nil unless LOCATED_PRECISIONS.include?(ev.geocode_precision)

      ev.geocode_place_name.presence
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
