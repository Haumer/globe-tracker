require "digest"
require "set"

class NewsStoryClusterer
  GENERAL_EVENT_TYPES = %w[actor_mention mentioned_relationship].freeze
  # "information" belongs here: both FAMILY_WINDOWS and FAMILY_MAX_DISTANCE_KM
  # define tuned values for it, so it was always meant to cluster. Omitting it
  # here meant every accusation_statement claim -- about 120 a day, the fourth
  # most common type we extract -- was parsed, scored, actor-linked, written to
  # news_claims, and then dropped on the floor by build_payload.
  CLUSTERABLE_EVENT_FAMILIES = Set.new(%w[
    conflict cyber diplomacy disaster economy humanitarian information
    infrastructure justice politics security transport
  ]).freeze
  DEFAULT_WINDOW = 36.hours
  DEFAULT_MAX_DISTANCE_KM = 250.0
  MATCH_THRESHOLD = 0.67

  # The floor below which two reports have not been shown to be the same story.
  #
  # Everything else in score_cluster is close to a constant for any pair that
  # gets as far as being scored. Matching event_type is worth 0.25, being inside
  # the family window is worth up to 0.15, and the location term contributes
  # 0.35 * 0.20 whenever either side's place is unknown -- which is most of the
  # corpus, because NewsPlaceResolver correctly refuses to answer rather than
  # return a masthead. That is 0.455 before a single word is compared, so one
  # shared actor at 0.25 carries a pair over MATCH_THRESHOLD with *no* words in
  # common at all. Two stories that share only "Israel" are then one story.
  #
  # Measured, not asserted: 400 pairs of headlines that are co-clustered today
  # were labelled same-story / different-story on meaning alone, independently
  # of any lexical metric. 73.8% of current merges are wrong. Vetoing below this
  # floor takes that to 35.5% while keeping 85.7% of the true merges.
  #
  # 0.22 rather than the marginally higher-scoring 0.24 because 0.26 falls off a
  # cliff -- recall drops 82% -> 70% over two hundredths -- and a threshold
  # picked on the flat part of a curve survives the corpus drifting. Weighting
  # text more heavily instead, or raising MATCH_THRESHOLD, was tried and scored
  # worse at every operating point: both shed true merges faster than false ones
  # because they move the constants too.
  MINIMUM_TEXT_SIMILARITY = 0.22

  # The floor below which two headlines do not mean the same thing.
  #
  # MINIMUM_TEXT_SIMILARITY asks whether two reports share words. That is close
  # to exhausted -- it took the share of merges that are really the same story
  # from 24.3% to 47.0%, and the errors left over are semantic. "Israel strikes
  # targets near Isfahan" and "Explosions heard in central Iran after suspected
  # Israeli attack" are one airstrike written by two newsrooms; the stem barely
  # connects them, and nothing lexical connects a story to its own follow-up.
  #
  # Measured on 300 co-clustered pairs from the post-fix rebuild, labelled
  # same-story / different-story on meaning alone. The embedding separates the
  # two populations at AUC 0.916 against 0.721 for the stem, on the same pairs.
  # This table is a *filter* over pairs that already exist, which is known to
  # run optimistic -- re-clustering seeks out passing pairs the old code never
  # formed -- so it is what the bounds were chosen on, not what they deliver.
  # Verified by two full rebuilds rather than by this table; see hard_veto?.
  #
  #   cosine floor   precision   keeps true merges
  #   (none)             47.0%       100%
  #   0.45               57.6%        99.3%
  #   0.50               65.9%        97.2%
  #   0.55               75.0%        93.6%
  #   0.60               82.7%        87.9%
  #   0.65               88.9%        73.8%
  #
  # 0.50 because of how the pairs it discards are distributed rather than how
  # many: below 0.50 only 4.3% of the pairs are the same story, so the floor is
  # buying most of its precision out of a population that is 96% wrong.
  # Between it and HEADLINE_COSINE_CERTAIN the split is 51% -- a coin flip, and
  # 44% of all pairs -- which is why that range goes to a model rather than to
  # a constant. A floor high enough to be precise on its own, 0.65, throws away
  # a quarter of the true merges, which is what the band exists to avoid.
  #
  # Tuned at 256 dimensions. The absolute value does not survive a change of
  # width or model; see NewsHeadlineEmbeddingService::DIMENSION_CHOICE.
  MINIMUM_HEADLINE_COSINE = 0.50

  # The cosine above which the embedding decides on its own, measured on the
  # same 300 pairs: at 0.70 a merge is right 90.9% of the time, which is at the
  # ceiling of what this can be measured against at all -- two competent human
  # referees agree on only 87.7% of these pairs, because "is a continuing
  # episode the same story?" is genuinely fuzzy.
  #
  # Everything between this and MINIMUM_HEADLINE_COSINE is the overlap of the
  # two populations, 44% of the pairs that get this far and a 51% coin flip
  # inside, which is why it goes to NewsClusterAdjudicator rather than to a
  # constant placed somewhere in the middle of it.
  #
  # Verified end to end by three full rebuilds of the clone over the same 17,061
  # articles, differing only by the change, 600 labelled pairs and 80 judged
  # clusters per arm:
  #
  #                        baseline   + floor   + adjudication
  #   pair precision         56.7%     63.5%      76.3%
  #   cluster purity         71.5%     82.8%      89.5%
  #   clusters 100% pure     37.5%     51.3%      73.8%
  #   asserted pairs         7,875     5,529      5,056
  #   est. correct pairs     4,463     3,511      3,859
  #
  # Report the two together: pair precision punishes one bad member n-1 times,
  # so a 27-member cluster with a single outlier loses 26 pairs and reads far
  # worse than the one bad member it actually has.
  #
  # 76.3% is measured against a judge-agreement ceiling of 87.7% -- two
  # competent referees disagree on one of these pairs in eight -- so the
  # remaining gap is not all error and is not all recoverable.
  HEADLINE_COSINE_CERTAIN = 0.70

  # How many of the undecided candidates the adjudicator is shown. Three because
  # the model is being asked to compare the alternatives against each other, and
  # a longer list is what made RegistryEntityResolver stop answering "none":
  # given more options it starts finding one plausible.
  ADJUDICATION_CANDIDATES = 3

  # How many member headlines the floor is checked against. A cluster asserts
  # that every one of its members is the same story as every other, so gating
  # only the incoming article against the lead leaves the member-to-member pairs
  # never checked at all: measured on a rebuild of the clone, those ungated
  # pairs ran at 5.0% precision while the gated ones ran at 48.8%. Checking
  # every member instead of just the lead is complete linkage rather than
  # centroid attachment, and it costs 2.5% of the true merges.
  #
  # Capped because the check is linear in members and the tokens are carried in
  # the cluster's metadata; clusters above this size are gated against a sample.
  MEMBER_TITLE_SAMPLE = 20

  # Two articles count as the same wire copy when their headlines are this
  # close. Deliberately far above MATCH_THRESHOLD: clustering asks "same
  # story?", this asks "same text?". Independent newsrooms covering one event
  # write different headlines; syndicated copy carries the origin's verbatim.
  SYNDICATION_TITLE_SIMILARITY = 0.85
  # Corroboration keeps adding confidence up to this many independent sources
  # (and articles) instead of saturating at the old hard caps of 3 and 4.
  SOURCE_FACTOR_SATURATION = 12
  COVERAGE_FACTOR_SATURATION = 25
  STRICT_LOCATION_EVENT_TYPES = %w[ground_operation accusation_statement arrest_detention protest].freeze

  FAMILY_WINDOWS = {
    "conflict" => 18.hours,
    "cyber" => 36.hours,
    "diplomacy" => 72.hours,
    "disaster" => 24.hours,
    "economy" => 48.hours,
    "humanitarian" => 48.hours,
    "information" => 24.hours,
    "infrastructure" => 24.hours,
    "justice" => 36.hours,
    "politics" => 48.hours,
    "security" => 18.hours,
    "transport" => 24.hours,
  }.freeze

  FAMILY_MAX_DISTANCE_KM = {
    "conflict" => 175.0,
    "cyber" => 400.0,
    "diplomacy" => 750.0,
    "disaster" => 350.0,
    "economy" => 600.0,
    "humanitarian" => 500.0,
    "information" => 400.0,
    "infrastructure" => 250.0,
    "justice" => 300.0,
    "politics" => 300.0,
    "security" => 200.0,
    "transport" => 250.0,
  }.freeze

  COMPATIBLE_EVENT_GROUPS = [
    %w[airstrike missile_attack],
    %w[negotiation summit agreement diplomatic_contact],
    %w[sanction_action trade_measure],
  ].map(&:to_set).freeze

  class << self
    def assign_records(records)
      return records if records.blank?

      contexts = build_record_contexts(records)
      payloads = load_payloads(contexts)
      assignments = {}

      payloads.sort_by { |payload| payload[:published_at] || payload[:fetched_at] || Time.current }.each do |payload|
        assignments[payload[:news_article_id]] = assign_payload(payload)
      end

      article_ids = contexts.keys
      unassigned_ids = article_ids - assignments.keys
      unassigned_ids.each { |article_id| clear_assignment(article_id) }
      apply_assignments(assignments)

      records.each do |record|
        article_id = fetch(record, :news_article_id)
        assignment = assignments[article_id]
        record[:story_cluster_id] = assignment&.dig(:cluster_key)
      end

      records
    rescue StandardError => e
      Rails.logger.warn("NewsStoryClusterer: #{e.message}")
      records
    end

    def recluster_article(article_or_id)
      article = article_or_id.is_a?(NewsArticle) ? article_or_id : NewsArticle.find_by(id: article_or_id)
      return nil unless article

      context = {
        article.id => {
          published_at: article.published_at,
          fetched_at: article.fetched_at,
          title: article.title,
          summary: article.summary,
          content_scope: article.content_scope,
          source_id: article.news_source_id,
        },
      }
      payload = load_payloads(context).first
      if payload
        assignment = assign_payload(payload)
        apply_assignments(article.id => assignment)
        assignment[:cluster_key]
      else
        clear_assignment(article.id)
        nil
      end
    end

    def rebuild_all(batch_size: 500)
      NewsStoryMembership.delete_all
      NewsStoryCluster.delete_all
      NewsEvent.update_all(story_cluster_id: nil, updated_at: Time.current)

      total = 0
      NewsArticle.where.not(content_scope: "out_of_scope")
        .where.not(title: nil)
        .order(Arel.sql("COALESCE(published_at, fetched_at, created_at) ASC"))
        .find_in_batches(batch_size: batch_size) do |batch|
          batch_records = batch.map do |article|
            event = article.news_events.max_by { |entry| entry.published_at || entry.fetched_at || entry.created_at }
            {
              news_article_id: article.id,
              title: article.title,
              summary: article.summary,
              published_at: article.published_at,
              fetched_at: article.fetched_at,
              content_scope: article.content_scope,
              name: event&.name,
              latitude: event&.latitude,
              longitude: event&.longitude,
              news_source_id: article.news_source_id,
            }
          end
          assign_records(batch_records)
          total += batch_records.size
        end

      total
    end

    private

    def build_record_contexts(records)
      records.each_with_object({}) do |record, contexts|
        article_id = fetch(record, :news_article_id)
        next if article_id.blank?

        existing = contexts[article_id] || {}
        contexts[article_id] = {
          title: fetch(record, :title) || existing[:title],
          summary: fetch(record, :summary) || existing[:summary],
          published_at: normalize_time(fetch(record, :published_at)) || existing[:published_at],
          fetched_at: normalize_time(fetch(record, :fetched_at)) || existing[:fetched_at],
          # Deliberately not seeded from the record's :name. On a news record
          # that field is frequently the publisher, and seeding it here is how
          # "France 24" became one of the most common places in the graph.
          # build_payload resolves the location from the persisted NewsEvent's
          # geocode_* columns instead, which record how each fix was derived.
          location_name: existing[:location_name],
          latitude: fetch(record, :latitude) || existing[:latitude],
          longitude: fetch(record, :longitude) || existing[:longitude],
          content_scope: fetch(record, :content_scope) || existing[:content_scope],
          source_id: fetch(record, :news_source_id) || existing[:source_id],
        }
      end
    end

    def load_payloads(contexts)
      article_ids = contexts.keys
      return [] if article_ids.empty?

      articles = NewsArticle.includes(:news_source, :news_events, news_claims: { news_claim_actors: :news_actor })
        .where(id: article_ids)
        .to_a
      ensure_headline_embeddings(articles, contexts)

      articles.filter_map do |article|
        claim = article.news_claims.find(&:primary?)
        context = contexts[article.id] || {}
        build_payload(article, claim, context)
      end
    end

    def build_payload(article, claim, context)
      return nil if article.content_scope == "out_of_scope"
      return nil if claim.blank?
      return nil if claim.event_family == "general"
      return nil unless CLUSTERABLE_EVENT_FAMILIES.include?(claim.event_family)
      return nil if GENERAL_EVENT_TYPES.include?(claim.event_type)

      event = article.news_events.max_by { |entry| entry.published_at || entry.fetched_at || entry.created_at }
      actors = claim.news_claim_actors.sort_by(&:position).filter_map do |claim_actor|
        actor = claim_actor.news_actor
        next unless actor

        {
          canonical_key: actor.canonical_key,
          name: actor.name,
          role: claim_actor.role,
          actor_type: actor.actor_type,
        }
      end

      title = context[:title] || article.title
      summary = context[:summary] || article.summary
      published_at = context[:published_at] || claim.published_at || article.published_at || event&.published_at
      fetched_at = context[:fetched_at] || article.fetched_at || event&.fetched_at
      # Never event&.name -- that is the publisher. NewsPlaceResolver works from
      # the geocode_* columns and returns nothing rather than a masthead, so a
      # blank location here means "we do not know", which is a usable signal.
      # It used to mean nothing at all, because the slot was always filled.
      location_name = scrub_location_name(context[:location_name] || NewsPlaceResolver.call(event).name)
      latitude = numeric_coordinate(context[:latitude] || event&.latitude)
      longitude = numeric_coordinate(context[:longitude] || event&.longitude)
      return nil if strict_location_event_type?(claim.event_type) && location_name.blank? && (latitude.nil? || longitude.nil?)

      {
        news_article_id: article.id,
        content_scope: context[:content_scope] || article.content_scope,
        source_id: context[:source_id] || article.news_source_id,
        source_kind: article.news_source&.source_kind,
        title: title,
        summary: summary,
        event_family: claim.event_family,
        event_type: claim.event_type,
        claim_confidence: claim.confidence.to_f,
        extraction_confidence: claim.extraction_confidence.to_f,
        actor_confidence: claim.actor_confidence.to_f,
        event_confidence: claim.event_confidence.to_f,
        source_reliability: claim.source_reliability.to_f,
        verification_status: claim.verification_status,
        geo_precision: claim.geo_precision,
        geo_confidence: claim.geo_confidence.to_f,
        claim_provenance: claim.provenance || {},
        published_at: published_at,
        fetched_at: fetched_at,
        location_name: location_name,
        latitude: latitude,
        longitude: longitude,
        actors: actors,
        text_tokens: normalized_tokens([ title, summary ].compact.join(" ")),
        # Headline alone, kept apart from text_tokens. The floor in hard_veto?
        # compares one headline against one headline; folding the summary into
        # that side makes the comparison asymmetric and inflates it.
        title_tokens: normalized_tokens(title),
        # Written a moment ago by ensure_headline_embeddings, or already on the
        # row from news:backfill_headline_embeddings. An article still without
        # one -- API down, key missing -- is clustered on the lexical floor
        # alone rather than sent to a singleton.
        #
        # Gated on the digest rather than on the title matching, because callers
        # pass the title from the feed record and the stored vector is of the
        # title on the row -- when a later poll revises a headline the two drift,
        # and comparing this article's words against another headline's vector
        # is a wrong answer rather than a missing one. The digest is over the
        # prepared text, so a differing publisher suffix is not a mismatch.
        title_embedding: embedding_for(article, title),
      }
    end

    def assign_payload(payload)
      cluster, score = best_cluster_for(payload)
      cluster ||= create_cluster_for(payload)
      score ||= 1.0

      {
        cluster: cluster,
        cluster_key: cluster.cluster_key,
        match_score: score.round(3),
        article_id: payload[:news_article_id],
      }
    end

    # Three tiers. Below MINIMUM_HEADLINE_COSINE hard_veto? has already rejected
    # the cluster; at or above HEADLINE_COSINE_CERTAIN the embedding is right on
    # its own and the merge is taken; in between the two populations overlap and
    # no constant can separate them, so the question goes to a model.
    def best_cluster_for(payload)
      scored = candidate_clusters(payload).filter_map do |cluster|
        score = score_cluster(payload, cluster)
        next if score.nil? || score < MATCH_THRESHOLD

        [ cluster, score ]
      end
      return [ nil, nil ] if scored.empty?

      # Position is part of the sort key because Ruby's sort_by is not stable
      # and score ties are common -- score_cluster is mostly constants. Without
      # it, two rebuilds of the same corpus disagree on which cluster an article
      # joins, which is enough to move the cluster count between arms of an
      # experiment that is supposed to differ only by the change under test.
      # Ties go to the earlier candidate, i.e. the more recently seen cluster,
      # which is what the previous max-scan did.
      ranked = scored.each_with_index.sort_by { |(_cluster, score), index| [ -score, index ] }.map(&:first)
      certain, undecided = ranked.partition { |cluster, _score| headline_certain?(payload, cluster) }
      # A certain candidate wins even where an undecided one scores higher.
      # score_cluster is mostly constants -- that is the defect this whole line
      # of work started from -- while the cosine separates same-story from
      # different-story at AUC 0.916, so it is the better of the two signals to
      # rank on when they disagree. It also spends nothing.
      return certain.first if certain.any?

      adjudicated(payload, undecided.first(ADJUDICATION_CANDIDATES))
    end

    # True when every member is far enough from the incoming headline to decide
    # without a model, and -- deliberately -- when there is nothing to measure.
    # An article or cluster with no embedding falls back to the behaviour it had
    # before embeddings existed rather than to a model call it cannot inform.
    def headline_certain?(payload, cluster)
      cosines = headline_cosines(payload, cluster)
      return true if cosines.empty?

      cosines.min >= HEADLINE_COSINE_CERTAIN
    end

    def adjudicated(payload, undecided)
      return [ nil, nil ] if undecided.empty?

      verdict = NewsClusterAdjudicator.call(
        title: payload[:title],
        candidates: undecided.map { |cluster, _score| adjudication_candidate(cluster) }
      )
      # Not reached, rather than answered "none". An unavailable model leaves the
      # decision where it was before the model existed -- the band was merged
      # outright then -- because the alternative failure mode is that an API
      # outage silently fragments the corpus into singletons, which no later
      # pass revisits. Same reasoning as the missing-embedding fallback.
      return undecided.first unless verdict.called
      return [ nil, nil ] unless verdict.chose?

      undecided[verdict.index]
    end

    def adjudication_candidate(cluster)
      {
        titles: member_titles(cluster),
        # Clean on any cluster this code wrote: predominant_location takes it
        # from NewsPlaceResolver, which returns nothing rather than a masthead.
        # Clusters written before the resolver landed still carry feed labels
        # and never self-heal, so until those age out the model occasionally
        # sees "GN: World" as a place. It reads the member headlines too.
        location_name: cluster.location_name,
        actors: Array(cluster.metadata["actor_names"]),
        first_seen_at: cluster.first_seen_at,
        last_seen_at: cluster.last_seen_at,
      }
    end

    def member_titles(cluster)
      ids = Array(cluster.provenance["article_ids"]).first(MEMBER_TITLE_SAMPLE)
      return [ cluster.canonical_title ].compact if ids.empty?

      by_id = NewsArticle.where(id: ids).pluck(:id, :title).to_h
      ids.filter_map { |id| by_id[id] }.presence || [ cluster.canonical_title ].compact
    end

    def candidate_clusters(payload)
      timestamp = payload[:published_at] || payload[:fetched_at] || Time.current
      window = clustering_window(payload[:event_family])

      NewsStoryCluster.where(event_family: payload[:event_family], content_scope: payload[:content_scope])
        .where("last_seen_at >= ?", timestamp - window)
        .order(last_seen_at: :desc)
        .limit(150)
    end

    def score_cluster(payload, cluster)
      return nil if cluster.event_family != payload[:event_family]

      timestamp = payload[:published_at] || payload[:fetched_at] || Time.current
      time_gap = (timestamp - cluster.last_seen_at).abs
      window = clustering_window(payload[:event_family])
      return nil if time_gap > window

      event_score = event_type_score(payload[:event_type], cluster.event_type)
      return nil if event_score.zero?

      actor_score = actor_overlap_score(payload, cluster)
      location_score = location_match_score(payload, cluster)
      text_score = text_similarity(payload[:text_tokens], Set.new(Array(cluster.metadata["text_tokens"])))
      time_score = 1.0 - [ time_gap / window.to_f, 1.0 ].min

      return nil if hard_veto?(payload, cluster, actor_score, location_score, text_score)

      (event_score * 0.25) +
        (actor_score * 0.25) +
        (location_score * 0.20) +
        (time_score * 0.15) +
        (text_score * 0.15)
    end

    def hard_veto?(payload, cluster, actor_score, location_score, text_score)
      # Headline against headline, deliberately NOT against text_score.
      #
      # text_score compares the incoming article to metadata["text_tokens"],
      # which is the union of every member's tokens and grows without bound. Its
      # containment half is then the share of the incoming headline found
      # *anywhere* in the cluster, which approaches 1.0 for any cluster large
      # enough -- so a floor applied there stops binding exactly where the
      # cluster is already big enough to do damage. Measured on a full rebuild
      # of the clone with the floor on text_score: 77.7% of the wrong merges
      # that survived had pairwise similarity below the floor and were admitted
      # by the bag alone.
      #
      # canonical_title is the lead member's headline, so this asks the question
      # the eval asked: are these two reports the same story?
      payload_tokens = payload[:title_tokens] || normalized_tokens(payload[:title])
      anchors = member_title_tokens(cluster)
      # No words to compare is no evidence, not weak evidence. text_similarity
      # returns 0.2 for an empty set on either side, which would otherwise sit
      # just under the floor and read as a real measurement.
      return true if payload_tokens.blank? || anchors.empty?
      return true if anchors.any? { |anchor| text_similarity(payload_tokens, anchor) < MINIMUM_TEXT_SIMILARITY }

      # The semantic floor, deliberately *after* the lexical one and not merged
      # with it. Two reasons, one of them arithmetic:
      #
      # A cosine is a 256-dimension dot product, and this runs against every
      # member of every candidate cluster -- up to 150 clusters of up to 20
      # members for each of 17,061 articles on a rebuild, which is 13 billion
      # multiply-adds in Ruby if it runs first. Behind the lexical floor it runs
      # only on the pairs lexical already admitted, which is a few per article.
      #
      # The second reason is that the two floors answer different questions and
      # both must hold: shared words without shared meaning is a topic, and
      # shared meaning without shared words is usually the same *kind* of event
      # somewhere else. A merge needs both.
      #
      # Complete linkage, exactly like the lexical floor above: a cluster
      # asserts every member is the same story as every other, so one member
      # below the floor vetoes the whole cluster rather than being averaged away
      # by the rest.
      #
      # This linkage, not the floor, is what recall costs. Measured against the
      # baseline arm's labelled pairs: a *pairwise* floor at 0.50 keeps 99.4% of
      # the true merges, but the rebuild that applies it keeps only 73.2%. Of
      # the 45 true merges lost, 44 had a pairwise cosine above the floor --
      # median 0.67 -- and all 45 articles still clustered, just not together.
      # They were vetoed by some *other* member of the cluster they belonged in,
      # and then went somewhere else.
      #
      # So lowering the floor would buy back almost nothing, and the lever for
      # recall is the linkage rule or a later merge pass over cluster centroids.
      # Complete linkage costs the lexical floor 2.5% of true merges and costs
      # this one an order of magnitude more, because a continuing episode
      # legitimately drifts in meaning across a day of coverage while it keeps
      # reusing the same words.
      return true if headline_cosines(payload, cluster).any? { |cosine| cosine < MINIMUM_HEADLINE_COSINE }

      return true if actor_score.zero? && location_score < 0.5 && text_score < 0.3

      payload_place = normalize_location_token(payload[:location_name])
      cluster_place = normalize_location_token(cluster.location_name)
      if payload_place.blank? && cluster_place.blank?
        return true if text_score < 0.4 && actor_score < 0.6
      end

      if strict_location_event_type?(payload[:event_type]) || strict_location_event_type?(cluster.event_type)
        return true if payload_place.blank? && cluster_place.blank? && text_score < 0.55
      end

      payload_lat = payload[:latitude]
      payload_lng = payload[:longitude]
      cluster_lat = cluster.latitude
      cluster_lng = cluster.longitude
      if payload_lat && payload_lng && cluster_lat && cluster_lng
        distance = haversine_km(payload_lat, payload_lng, cluster_lat, cluster_lng)
        return true if distance > (max_distance_km(payload[:event_family]) * 2.0)
      end

      false
    end

    def create_cluster_for(payload)
      timestamp = payload[:published_at] || payload[:fetched_at] || Time.current
      cluster_key = cluster_key_for(payload, timestamp)
      existing_cluster = NewsStoryCluster.find_by(cluster_key: cluster_key)
      return existing_cluster if existing_cluster

      attributes = cluster_attributes_for(payload, timestamp)

      NewsStoryCluster.create!(attributes.merge(cluster_key: cluster_key))
    rescue ActiveRecord::RecordNotUnique
      NewsStoryCluster.find_by!(cluster_key: cluster_key)
    end

    def cluster_key_for(payload, timestamp)
      actor_token = payload[:actors].map { |actor| actor[:canonical_key] }.sort.join("-")
      place_token = normalize_location_token(payload[:location_name])
      time_token = timestamp.utc.strftime("%Y%m%d%H")
      raw_key = [
        payload[:event_family],
        payload[:event_type],
        actor_token.presence,
        place_token.presence,
        time_token,
        payload[:news_article_id],
      ].compact.join("|")

      Digest::SHA1.hexdigest(raw_key)[0, 12]
    end

    def cluster_attributes_for(payload, timestamp)
      {
        canonical_title: payload[:title].to_s.scrub("")[0...500],
        content_scope: payload[:content_scope],
        event_family: payload[:event_family],
        event_type: payload[:event_type],
        location_name: payload[:location_name],
        latitude: payload[:latitude],
        longitude: payload[:longitude],
        geo_precision: geo_precision_for(payload),
        first_seen_at: timestamp,
        last_seen_at: timestamp,
        article_count: 0,
        source_count: 0,
        cluster_confidence: payload[:claim_confidence].presence || 0.5,
        source_reliability: payload[:source_reliability].to_f.round(3),
        geo_confidence: payload[:geo_confidence].to_f.round(3),
        verification_status: payload[:verification_status].presence || "single_source",
        metadata: {
          "actor_keys" => payload[:actors].map { |actor| actor[:canonical_key] },
          "actor_roles" => payload[:actors].map { |actor| { "key" => actor[:canonical_key], "role" => actor[:role], "name" => actor[:name] } },
          "text_tokens" => payload[:text_tokens].to_a,
          "member_title_tokens" => [ payload[:title_tokens].to_a ],
        },
        provenance: {
          "lead_article_id" => payload[:news_article_id],
          "lead_source_id" => payload[:source_id],
          "source_ids" => Array(payload[:source_id]).compact,
          "article_ids" => [ payload[:news_article_id] ],
          "claim_provenance" => payload[:claim_provenance],
        },
      }
    end

    def apply_assignments(assignments)
      assignments.each_value do |assignment|
        persist_assignment(assignment)
      end
    end

    def persist_assignment(assignment)
      article_id = assignment[:article_id]
      cluster = assignment[:cluster]
      now = Time.current

      membership = NewsStoryMembership.find_or_initialize_by(news_article_id: article_id)
      previous_cluster = membership.persisted? ? membership.news_story_cluster : nil
      membership.update!(
        news_story_cluster: cluster,
        match_score: assignment[:match_score],
        primary: true,
        metadata: {
          "assigned_at" => now.iso8601,
        },
      )

      NewsEvent.where(news_article_id: article_id).update_all(
        story_cluster_id: cluster.cluster_key,
        updated_at: now
      )

      recalculate_cluster!(cluster)
      recalculate_cluster!(previous_cluster) if previous_cluster && previous_cluster.id != cluster.id
    end

    def clear_assignment(article_id)
      membership = NewsStoryMembership.find_by(news_article_id: article_id)
      previous_cluster = membership&.news_story_cluster
      membership&.destroy!
      NewsEvent.where(news_article_id: article_id).update_all(story_cluster_id: nil, updated_at: Time.current)
      recalculate_cluster!(previous_cluster) if previous_cluster
    end

    def recalculate_cluster!(cluster)
      return unless cluster

      memberships = cluster.news_story_memberships.includes(news_article: [ :news_source, :news_events, { news_claims: { news_claim_actors: :news_actor } } ]).to_a
      if memberships.empty?
        cluster.destroy!
        return
      end

      article_payloads = memberships.filter_map do |membership|
        article = membership.news_article
        claim = article.news_claims.find(&:primary?)
        payload = build_payload(article, claim, {})
        next unless payload

        payload.merge(match_score: membership.match_score)
      end

      # A member whose payload will not rebuild must not take the whole cluster
      # down with it. build_payload returns nil for any member it cannot fully
      # reconstruct -- most often a strict-location event type whose location
      # lives on a NewsEvent row -- and this used to `return` on that, leaving a
      # cluster that still had memberships reporting article_count: 0 with a
      # last_seen_at frozen at creation. Frozen last_seen_at is the damaging
      # half: candidate_clusters only considers clusters seen inside the family
      # window, so the cluster silently stopped being a candidate for anything
      # and every later article on the same story opened a new singleton.
      # Fall back to what the memberships alone can tell us.
      if article_payloads.empty?
        cluster.update!(
          article_count: memberships.size,
          last_seen_at: [ cluster.last_seen_at, *memberships.map(&:updated_at) ].compact.max
        )
        return
      end

      lead_payload = article_payloads.max_by { |payload| lead_score(payload) }
      timestamps = article_payloads.map { |payload| payload[:published_at] || payload[:fetched_at] || Time.current }
      actor_roles = article_payloads.flat_map { |payload| payload[:actors] }
      actor_keys = actor_roles.map { |actor| actor[:canonical_key] }.uniq
      source_ids = article_payloads.filter_map { |payload| payload[:source_id] }.uniq
      coordinates = article_payloads.filter_map do |payload|
        lat = payload[:latitude]
        lng = payload[:longitude]
        next unless lat && lng

        [ lat, lng ]
      end
      latitude = coordinates.any? ? coordinates.sum(&:first) / coordinates.size.to_f : nil
      longitude = coordinates.any? ? coordinates.sum(&:last) / coordinates.size.to_f : nil
      location_name = predominant_location(article_payloads)
      avg_claim_confidence = article_payloads.sum { |payload| payload[:claim_confidence].to_f } / article_payloads.size.to_f
      avg_source_reliability = article_payloads.sum { |payload| payload[:source_reliability].to_f } / article_payloads.size.to_f
      avg_geo_confidence = article_payloads.sum { |payload| payload[:geo_confidence].to_f } / article_payloads.size.to_f
      avg_match_score = article_payloads.sum { |payload| payload[:match_score].to_f } / article_payloads.size.to_f
      syndication = syndication_groups(article_payloads)
      independent_source_ids = syndication.filter_map { |group| group[:source_ids].first }.uniq
      source_factor = saturating_factor(independent_source_ids.size, SOURCE_FACTOR_SATURATION)
      coverage_factor = saturating_factor(article_payloads.size, COVERAGE_FACTOR_SATURATION)
      cluster_confidence = [
        (avg_claim_confidence * 0.45) + (avg_match_score * 0.25) + (avg_source_reliability * 0.15) + (avg_geo_confidence * 0.05) + (source_factor * 0.05) + (coverage_factor * 0.05),
        0.99,
      ].min.round(3)
      # Corroboration counts *independent* newsrooms, not outlets. Forty papers
      # running the same wire copy is one newsroom, and treating it as forty
      # would let syndication manufacture confidence.
      verification_status = if independent_source_ids.size >= 2
        "multi_source"
      else
        lead_payload[:verification_status].presence || "single_source"
      end

      cluster.update!(
        canonical_title: lead_payload[:title].to_s.scrub("")[0...500],
        content_scope: lead_payload[:content_scope],
        event_family: predominant_value(article_payloads, :event_family) || lead_payload[:event_family],
        event_type: predominant_value(article_payloads, :event_type) || lead_payload[:event_type],
        location_name: location_name,
        latitude: latitude,
        longitude: longitude,
        geo_precision: predominant_value(article_payloads, :geo_precision) || (coordinates.any? ? "point" : (location_name.present? ? "named_area" : "unknown")),
        first_seen_at: timestamps.min,
        last_seen_at: timestamps.max,
        article_count: article_payloads.size,
        source_count: source_ids.size,
        cluster_confidence: cluster_confidence,
        source_reliability: avg_source_reliability.round(3),
        geo_confidence: avg_geo_confidence.round(3),
        verification_status: verification_status,
        lead_news_article_id: lead_payload[:news_article_id],
        metadata: {
          "actor_keys" => actor_keys,
          "actor_roles" => actor_roles.map { |actor| { "key" => actor[:canonical_key], "role" => actor[:role], "name" => actor[:name] } }.uniq,
          "actor_names" => actor_roles.map { |actor| actor[:name] }.uniq,
          "source_ids" => source_ids,
          "independent_source_ids" => independent_source_ids,
          "syndicated_article_count" => article_payloads.size - syndication.size,
          "text_tokens" => article_payloads.flat_map { |payload| payload[:text_tokens].to_a }.uniq,
          "member_title_tokens" => article_payloads.first(MEMBER_TITLE_SAMPLE)
            .map { |payload| payload[:title_tokens].to_a }.reject(&:empty?),
        },
        provenance: {
          "lead_article_id" => lead_payload[:news_article_id],
          "lead_source_id" => lead_payload[:source_id],
          "article_ids" => article_payloads.map { |payload| payload[:news_article_id] }.uniq,
          "source_ids" => source_ids,
          "source_kinds" => article_payloads.map { |payload| payload[:source_kind] }.compact.uniq,
          "claim_provenance" => article_payloads.map { |payload| payload[:claim_provenance] }.compact,
        },
      )
    end

    def lead_score(payload)
      score = payload[:claim_confidence].to_f
      score += 0.1 if payload[:summary].present?
      score += 0.1 if payload[:actors].any?
      score += 0.1 if payload[:source_kind] == "wire"
      score
    end

    def event_type_score(payload_event_type, cluster_event_type)
      return 1.0 if payload_event_type == cluster_event_type
      return 0.7 if compatible_event_types?(payload_event_type, cluster_event_type)

      0.0
    end

    def compatible_event_types?(left, right)
      COMPATIBLE_EVENT_GROUPS.any? { |group| group.include?(left) && group.include?(right) }
    end

    def strict_location_event_type?(event_type)
      STRICT_LOCATION_EVENT_TYPES.include?(event_type)
    end

    # Falls back to the cluster's own headline for rows written before member
    # headlines were carried, so an existing cluster is gated against one anchor
    # rather than none until recalculate_cluster! next rewrites it.
    def member_title_tokens(cluster)
      stored = Array(cluster.metadata["member_title_tokens"])
      return stored.map { |tokens| Set.new(Array(tokens)) } if stored.any?

      anchor = normalized_tokens(cluster.canonical_title)
      anchor.empty? ? [] : [ anchor ]
    end

    # Embed the headlines this run is about to score, and write the vectors to
    # the rows before anything reads them.
    #
    # headline_cosines and headline_certain? both fail open on a missing
    # vector: no embedding reads as "not measured", the gate never fires, and
    # the pair is settled on the lexical floor alone. That is the right
    # behaviour for a backfill still in progress -- and it is exactly why the
    # gate was inert for live traffic. Nothing on the ingest path had ever
    # written a vector, so only the rows news:backfill_headline_embeddings had
    # already reached were ever measured; every freshly polled article took the
    # pre-embedding path in silence, and the measured 56.7% -> 76.3% pair
    # precision applied to none of them.
    #
    # Only headlines that will actually be compared are embedded. An
    # out_of_scope article, or one whose claim never clears build_payload, is
    # never scored against anything, and those are most of the corpus.
    def ensure_headline_embeddings(articles, contexts)
      pending = articles.filter_map do |article|
        next unless embeddable?(article)

        title = (contexts.dig(article.id, :title) || article.title).to_s
        next if title.blank? || embedding_for(article, title)

        [ article, title ]
      end
      return if pending.empty?

      vectors = NewsHeadlineEmbeddingService.embed(pending.map(&:last))
      tag = NewsHeadlineEmbeddingService.model_tag

      pending.each_with_index do |(article, title), index|
        vector = vectors[index]
        next if vector.blank?

        digest = NewsHeadlineEmbeddingService.digest_for(title)
        NewsArticle.where(id: article.id).update_all(
          title_embedding: "{#{vector.join(',')}}",
          title_embedding_model: tag,
          title_embedding_digest: digest,
          updated_at: Time.current
        )
        # The loaded row is what build_payload reads a moment from now, so it
        # has to carry what the column now holds. update_all already wrote the
        # column, so none of this is pending a save.
        article.title_embedding = vector
        article.title_embedding_model = tag
        article.title_embedding_digest = digest
      end
    rescue StandardError => e
      # An embedding outage must never stop an article being clustered. The
      # cosine gate is an improvement on the lexical floor, not a dependency of
      # it, and the fail-open readers below already handle an absent vector.
      Rails.logger.warn("NewsStoryClusterer embedding: #{e.class} #{e.message}")
    end

    # The gate build_payload applies, asked before the part that costs money.
    def embeddable?(article)
      return false if article.content_scope == "out_of_scope"

      claim = article.news_claims.find(&:primary?)
      return false if claim.blank? || claim.event_family == "general"
      return false unless CLUSTERABLE_EVENT_FAMILIES.include?(claim.event_family)

      !GENERAL_EVENT_TYPES.include?(claim.event_type)
    end

    def embedding_for(article, title)
      vector = article.title_embedding
      return nil if vector.blank?
      # Rows embedded before the digest column carried a value are trusted only
      # when the caller is using the row's own title, which is what rebuild_all
      # and recluster_article both do.
      return vector if article.title_embedding_digest.blank? && title == article.title

      vector if article.title_embedding_digest == NewsHeadlineEmbeddingService.digest_for(title)
    end

    # Cosine of the incoming headline against each member headline the cluster
    # is gated on. Empty when either side has no embedding, which reads as "not
    # measured" and lets the pair through on the lexical floor alone -- the
    # pre-embedding behaviour. Failing open is deliberate: an embedding backfill
    # that has not finished, or an API that is down, must not silently send
    # every article to its own singleton, which is what failing closed would do.
    def headline_cosines(payload, cluster)
      vector = payload[:title_embedding]
      return [] if vector.blank?

      member_ids = Array(cluster.provenance["article_ids"]).first(MEMBER_TITLE_SAMPLE)
      return [] if member_ids.empty?

      member_embeddings(member_ids).filter_map do |member_vector|
        NewsHeadlineEmbeddingService.cosine(vector, member_vector)
      end
    end

    # Member vectors are read from news_articles rather than carried in the
    # cluster's metadata, unlike the token bags. Twenty members at 256 floats is
    # about 100KB of JSON per cluster and 385MB across the corpus, to store what
    # is already one indexed lookup away.
    #
    # Bounded, because the live path runs inside a long-lived worker: an
    # unbounded memo would hold every article the process has ever clustered.
    # Ruby hashes iterate in insertion order, so shift evicts the oldest.
    EMBEDDING_CACHE_LIMIT = 20_000

    def member_embeddings(member_ids)
      cache = (@embedding_cache ||= {})
      missing = member_ids.reject { |id| cache.key?(id) }
      if missing.any?
        NewsArticle.where(id: missing).pluck(:id, :title_embedding).each do |id, vector|
          cache[id] = vector.presence
        end
        # Anything the query did not answer for is absent, not pending: record
        # it so a cluster whose members predate the backfill is not re-queried
        # once per candidate scoring, for every article, forever.
        missing.each { |id| cache[id] = nil unless cache.key?(id) }
        cache.shift while cache.size > EMBEDDING_CACHE_LIMIT
      end

      member_ids.filter_map { |id| cache[id] }
    end

    def actor_overlap_score(payload, cluster)
      payload_keys = payload[:actors].map { |actor| actor[:canonical_key] }.to_set
      cluster_keys = Set.new(Array(cluster.metadata["actor_keys"]))
      return 0.4 if payload_keys.empty? && cluster_keys.empty?
      return 0.2 if payload_keys.empty? || cluster_keys.empty?

      intersection = (payload_keys & cluster_keys).size.to_f
      union = (payload_keys | cluster_keys).size.to_f
      return 0.0 if intersection.zero?

      intersection / union
    end

    def location_match_score(payload, cluster)
      payload_lat = payload[:latitude]
      payload_lng = payload[:longitude]
      cluster_lat = cluster.latitude
      cluster_lng = cluster.longitude
      if payload_lat && payload_lng && cluster_lat && cluster_lng
        distance = haversine_km(payload_lat, payload_lng, cluster_lat, cluster_lng)
        max_distance = max_distance_km(payload[:event_family])
        return 1.0 if distance <= (max_distance * 0.2)
        return 0.8 if distance <= (max_distance * 0.5)
        return 0.55 if distance <= max_distance

        return 0.0
      end

      payload_place = normalize_location_token(payload[:location_name])
      cluster_place = normalize_location_token(cluster.location_name)
      return 0.85 if payload_place.present? && payload_place == cluster_place
      return 0.35 if payload_place.blank? || cluster_place.blank?

      0.0
    end

    def text_similarity(tokens_a, tokens_b)
      set_a = Set.new(tokens_a)
      set_b = Set.new(tokens_b)
      return 0.2 if set_a.empty? || set_b.empty?

      intersection = (set_a & set_b).size.to_f
      union = (set_a | set_b).size.to_f
      smaller = [ set_a.size, set_b.size ].min.to_f

      jaccard = intersection / union
      containment = intersection / smaller
      [ jaccard, containment ].max
    end

    def predominant_location(payloads)
      counts = payloads.each_with_object(Hash.new(0)) do |payload, mapping|
        key = payload[:location_name].presence
        next unless key

        mapping[key] += 1
      end
      return nil if counts.empty?

      counts.max_by { |_key, count| count }&.first
    end

    def predominant_value(payloads, key)
      counts = payloads.each_with_object(Hash.new(0)) do |payload, mapping|
        value = payload[key].presence
        next unless value

        mapping[value] += 1
      end
      return nil if counts.empty?

      counts.max_by { |_value, count| count }&.first
    end

    def geo_precision_for(payload)
      return "point" if payload[:latitude] && payload[:longitude]
      return "named_area" if payload[:location_name].present?

      "unknown"
    end

    def max_distance_km(event_family)
      FAMILY_MAX_DISTANCE_KM[event_family] || DEFAULT_MAX_DISTANCE_KM
    end

    def clustering_window(event_family)
      FAMILY_WINDOWS[event_family] || DEFAULT_WINDOW
    end

    def haversine_km(lat1, lng1, lat2, lng2)
      rad_per_deg = Math::PI / 180
      r_km = 6371.0
      dlat_rad = (lat2 - lat1) * rad_per_deg
      dlng_rad = (lng2 - lng1) * rad_per_deg
      lat1_rad = lat1 * rad_per_deg
      lat2_rad = lat2 * rad_per_deg

      a = Math.sin(dlat_rad / 2)**2 +
        Math.cos(lat1_rad) * Math.cos(lat2_rad) * Math.sin(dlng_rad / 2)**2
      c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
      r_km * c
    end

    # Partition a cluster's articles into headline groups. Each group is one
    # piece of reporting as it spread: the origin plus every outlet that ran it
    # near-verbatim. The count of groups -- not of outlets -- is how much
    # independent corroboration a story actually has.
    #
    # Uses Jaccard alone rather than the max(jaccard, containment) used for
    # clustering. Containment reaches 1.0 whenever one headline is a subset of
    # another ("Strike hits depot" inside "Strike hits depot, 50 dead"), which
    # is normal between competing newsrooms and must not read as syndication.
    def syndication_groups(article_payloads)
      groups = []
      article_payloads.each do |payload|
        tokens = normalized_tokens(payload[:title])
        group = groups.find { |candidate| title_jaccard(candidate[:tokens], tokens) >= SYNDICATION_TITLE_SIMILARITY }
        if group
          group[:source_ids] << payload[:source_id] if payload[:source_id]
        else
          groups << { tokens: tokens, source_ids: [ payload[:source_id] ].compact }
        end
      end
      groups
    end

    def title_jaccard(tokens_a, tokens_b)
      set_a = Set.new(tokens_a)
      set_b = Set.new(tokens_b)
      return 0.0 if set_a.empty? || set_b.empty?

      union = (set_a | set_b).size.to_f
      return 0.0 if union.zero?

      (set_a & set_b).size / union
    end

    # Logarithmic so corroboration keeps paying off past the first few sources
    # while still flattening out. A hard cap at 3 made a 3-source story and a
    # 300-source story score identically once the source list grew.
    def saturating_factor(count, saturation)
      return 0.0 if count <= 0

      [ Math.log(1 + count) / Math.log(1 + saturation), 1.0 ].min
    end

    # Tokens are folded to a stem before comparison. Unfolded, "Israel strikes
    # targets near Isfahan" and "Explosions heard in central Iran after
    # suspected Israeli attack" -- one airstrike, two newsrooms -- share not one
    # token, because israel/israeli and strike/strikes are different strings.
    # That pair scores 0.0 exactly, and any text floor would reject the case the
    # clusterer exists for.
    #
    # A suffix strip followed by a six-character prefix, rather than a real
    # stemmer: measured against the same 400 labelled pairs it beat exact
    # matching at every floor, lifting the share of true merges kept from 81.9%
    # to 85.7% at equal precision. It is deliberately crude, because the failure
    # it must avoid is over-conflation -- six characters keeps iran/iraq and
    # gaza/gazprom apart, which a three-character prefix would not.
    STEM_SUFFIX = /(ings|ing|ies|ers|er|ed|es|s|ian|ish|i)\z/
    STEM_LENGTH = 6

    def normalized_tokens(text)
      text.to_s.downcase.scan(/[a-z0-9]{3,}/).reject do |token|
        %w[after against amid and are for from into near over says that the their these they this were with].include?(token)
      end.map { |token| token.sub(STEM_SUFFIX, "")[0, STEM_LENGTH] }.to_set
    end

    def normalize_location_token(value)
      value.to_s.downcase.gsub(/[^a-z0-9\s]/, " ").squeeze(" ").strip.presence
    end

    def scrub_location_name(value)
      value.to_s.scrub("").strip.presence&.slice(0, 200)
    end

    def numeric_coordinate(value)
      return nil if value.blank?

      value.to_f
    end

    def normalize_time(value)
      return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
      return nil if value.blank?

      Time.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def fetch(record, key)
      record[key] || record[key.to_s]
    end
  end
end
