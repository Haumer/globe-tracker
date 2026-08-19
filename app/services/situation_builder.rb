# Phase 2: group the clusters that are one story, and let ring 3 reach all of
# them.
#
# 83 clusters covered the Houthi/Red Sea story; 14 named a registry entity. The
# other 69 are the same story and reach nothing. Grouping them is what turns 14
# links into a situation with 83 members behind it.
#
# What is deliberately NOT done here: propagating the `names_entity` edge to
# members. A cluster that does not name Bab el-Mandeb does not name it, and
# asserting otherwise is how connectivity gets gamed -- grouping on the actor
# "Houthis" alone pulls in a jalapeño salmonella story, and propagation would
# link jalapeños to the strait. Instead the situation carries the entity, and the
# chain reads event -> situation -> entity -> ring 3. A wrong member then costs
# one bad membership rather than one bad claim about an asset.
class SituationBuilder
  ENTITY_TYPE = "situation".freeze
  MEMBERSHIP_ROLE = "in_situation".freeze
  CONCERNS = "concerns".freeze
  DERIVED_BY = "situation_builder_v1".freeze

  # An actor in more than this share of the window is describing the news, not a
  # story: "United States" 35.5%, "Iran" 27.8%, "Israel" 19.8% are noise, while
  # "Houthis" at 5.9% is a story. Measured per run, so it tracks the corpus.
  ACTOR_SPECIFICITY = 0.10

  # Mean pairwise Jaccard over member headlines. Half of all multi-article
  # clusters fall below this: the clusterer merges unrelated stories, and one
  # sampled cluster held a German drone alert, a salmonella outbreak and two
  # wildfire stories. Grouping those propagates the contamination, so they are
  # left out of situations entirely and counted, not silently dropped.
  COHERENCE_FLOOR = 0.06

  # A story needs corroboration to be a story.
  MINIMUM_MEMBERS = 2

  # The recency window situations are built over. Three days, because the board
  # answers "what is happening": a cluster last seen four days ago is not
  # happening, it is history -- and over 21 days an actor group is the actor's
  # whole news cycle rather than a story. The sweep in prune_stale retires
  # whatever falls out. Widen per run (rake DAYS=21) for a retrospective build.
  WINDOW_DAYS = 3

  STOPWORDS = %w[
    the a an and or of to in on for with as at by from is are was were be been
    it its this that has have had will would can could new says say said after
    over into up out about more than then them they not all any one two first
  ].to_set.freeze

  def self.call(days: WINDOW_DAYS, now: Time.current, actor_specificity: ACTOR_SPECIFICITY)
    new(days: days, now: now, actor_specificity: actor_specificity).call
  end

  # actor_specificity is injectable so the threshold itself can be tested
  # separately from everything built on top of it: in a fixture of two clusters
  # every actor occurs in 100% of them, and the production value would reject
  # them all.
  def initialize(days: WINDOW_DAYS, now: Time.current, actor_specificity: ACTOR_SPECIFICITY)
    @days = days
    @now = now
    @actor_specificity = actor_specificity
    @stats = Hash.new(0)
  end

  def call
    grouped = Hash.new { |hash, key| hash[key] = [] }

    clusters.each do |cluster|
      event = events_by_cluster[cluster.id]
      next @stats[:no_event] += 1 unless event

      unless coherent?(cluster)
        @stats[:incoherent] += 1
        next
      end

      key = grouping_key(cluster, event)
      next @stats[:no_key] += 1 unless key

      grouped[key] << [cluster, event]
    end

    built_keys = []
    grouped.each do |key, members|
      next @stats[:too_small] += 1 if members.size < MINIMUM_MEMBERS

      built_keys << persist(key, members).canonical_key
      @stats[:situations] += 1
      @stats[:members] += members.size
    end

    prune_stale(built_keys)
    @stats
  end

  private

  attr_reader :days, :now, :actor_specificity

  # The registry entity a member already names is a far stronger key than a
  # shared actor: two clusters naming Bab el-Mandeb are one story, two sharing
  # "Houthis" may be a shipping attack and a domestic politics piece. Actor is
  # the fallback, and only a specific one.
  #
  # The occurrence sits between them, and the ordering is load-bearing in both
  # directions. Below names_entity, because a report that names a strait is
  # about the strait even if a quake happened in the same country that week.
  # Above the actor fallback, because without it the rarest-actor rule files
  # stories that have no actor under whoever they happened to mention: the
  # 62-article cluster on the Colombia quake keyed on "United Nations" at 3.4%
  # and became a member of the UN situation.
  def grouping_key(cluster, event)
    entity_id = named_entity_ids[event.id]&.first
    return [:entity, entity_id] if entity_id

    occurrence_id = occurrence_ids[event.id]
    return [:entity, occurrence_id] if occurrence_id

    actor = specific_actor_for(event)
    return [:actor, actor] if actor

    place_id = place_key_for(event)
    return [:place, place_id] if place_id

    nil
  end

  # The place fallback, below actors on purpose: a story with a specific actor
  # is that actor's story wherever it happens, but a keyless cluster that
  # resolved to a real sub-country place is the story of that place -- Ceuta's
  # migrant surge, Kyiv under drones. Measured on the dev capture, 570 of 894
  # in-window clusters had no key at all and 246 of them shared a place with
  # another; this is the single largest recovery available without new coding.
  #
  # Two guards, both learned elsewhere. Country-named places are refused for
  # the reason country actors are: "Colombia" and "China" arrive as place-typed
  # entities, and keying on them would rebuild the every-story-about-a-country
  # group the actor exclusion exists to prevent. And the same specificity rule
  # applies -- a place carried by a large share of the window is describing the
  # news cycle, not a story.
  def place_key_for(event)
    place = event_place_entities[event.place_entity_id]
    return unless place
    return if country_place_names.include?(place.canonical_name.to_s.downcase)
    return if place_frequency[place.id].to_f >= actor_specificity

    place.id
  end

  def event_place_entities
    @event_place_entities ||= OntologyEntity
      .where(id: events_by_cluster.values.filter_map(&:place_entity_id).uniq,
             entity_type: NewsOntologySyncService::PLACE_ENTITY_TYPE)
      .index_by(&:id)
  end

  def place_frequency
    @place_frequency ||= begin
      total = [ event_ids.size, 1 ].max
      events_by_cluster.values.filter_map(&:place_entity_id)
        .tally.transform_values { |count| count.to_f / total }
    end
  end

  # Names that can never key a place situation. Principled classes rather than
  # a whack-a-mole denylist: country-scale names (the same rule as country
  # actors -- and COUNTRY_NAME_MAP alone misses Lebanon, Oman and friends,
  # which is why the claim extractor's state-actor names join it), geography
  # too big to be a story (continents, oceans, regions), and month names,
  # which the title geocoder occasionally mints as places ("August"). That
  # last one is upstream debt; it just should not become a situation while it
  # lasts. Anything junk that slips past lands in the emerging tier, dimmed.
  def country_place_names
    @country_place_names ||= begin
      countries = NewsGeocodable::COUNTRY_NAME_MAP.keys
      states = NewsClaimExtractor::ACTOR_DEFINITIONS
        .select { |actor| actor[:actor_type] == "state" }
        .map { |actor| actor[:name].downcase }
      regions = %w[africa asia europe antarctica oceania pacific atlantic arctic mediterranean] +
        [ "north america", "south america", "latin america", "middle east", "indian ocean" ]
      months = Date::MONTHNAMES.compact.map(&:downcase)

      (countries + states + regions + months).to_set
    end
  end

  # place:hazard:* entities are OntologyEntity rows like any registry asset, so
  # an occurrence key needs no new node type: persist, link_concerns and the
  # whole read side downstream work on it unchanged.
  def occurrence_ids
    @occurrence_ids ||= OntologyRelationship
      .where(source_node_type: "OntologyEvent", source_node_id: event_ids,
             relation_type: HazardOccurrenceLinkService::RELATION_TYPE)
      .pluck(:source_node_id, :target_node_id).to_h
  end

  def specific_actor_for(event)
    candidates = actor_ids_by_event[event.id].to_a - country_actor_ids
    return if candidates.empty?

    # Rarest wins: it carries the most information about which story this is.
    candidates.select { |id| actor_frequency[id].to_f < actor_specificity }
      .min_by { |id| actor_frequency[id].to_f }
  end

  # A country is a place, not a story. Frequency cannot make this call: "Japan"
  # appears in 6.0% of the window and "Houthis" in 5.9%, yet grouping on the
  # first produced a 62-member "Japan situation" holding every unrelated story
  # about the country. What separates them is already in the graph -- 67 of the
  # 79 actors carry a represents_country edge from OntologyV2IdentityService, and
  # the 12 that do not are exactly the story-shaped ones: Houthis, Hamas,
  # Hezbollah, Islamic State, Taliban, Rapid Support Forces.
  def country_actor_ids
    @country_actor_ids ||= OntologyRelationship
      .where(relation_type: OntologyV2IdentityService::REPRESENTS_COUNTRY,
             source_node_type: "OntologyEntity")
      .distinct.pluck(:source_node_id)
  end

  def persist(key, members)
    kind, reference = key
    situation = OntologySyncSupport.upsert_entity(
      canonical_key: "situation:#{kind}:#{reference}",
      entity_type: ENTITY_TYPE,
      canonical_name: situation_name(kind, reference, members),
      metadata: {
        "grouped_by" => kind.to_s,
        "member_count" => members.size,
        "derived_by" => DERIVED_BY,
        "first_seen_at" => members.map { |_, event| event.first_seen_at }.compact.min&.iso8601,
        "last_seen_at" => members.map { |_, event| event.last_seen_at }.compact.max&.iso8601,
        "built_at" => now.iso8601,
      }.compact
    )

    kept = members.map do |_cluster, event|
      OntologySyncSupport.persist_upsert(
        OntologyEventEntity,
        ontology_event: event,
        ontology_entity: situation,
        role: MEMBERSHIP_ROLE
      ) { |record| record.confidence = 0.7 }.id
    end

    # Membership is written as an event_entity rather than a relationship on
    # purpose. The scorecard's cross-domain metric reads relationships only, and
    # a situation is a news-side construct -- routing membership through it would
    # lift that number for every grouped cluster without any of them having
    # reached a physical thing. The reach is real through the concerns edge
    # below; it just is not this metric's to claim.
    OntologyEventEntity.where(ontology_entity: situation, role: MEMBERSHIP_ROLE)
      .where.not(id: kept).delete_all

    link_concerns(situation, kind, reference)
    situation
  end

  # The inverse of persist, which scheduled runs need and one-shot rake runs
  # never did: persist only upserts the groups that exist *now*, so a situation
  # whose story has left the window -- or whose members regrouped under another
  # key -- would stay on the board forever, at whatever member_count it last
  # had. Scoped to DERIVED_BY so nothing else's entities can be swept.
  #
  # Evidence rows are deleted explicitly: OntologyEntity's relationship
  # cascades are delete_all, which skips the relationships' own callbacks and
  # would orphan their evidence.
  def prune_stale(built_keys)
    stale = OntologyEntity.where(entity_type: ENTITY_TYPE)
      .where("metadata->>'derived_by' = ?", DERIVED_BY)
    stale = stale.where.not(canonical_key: built_keys) if built_keys.any?
    stale_ids = stale.pluck(:id)
    return if stale_ids.empty?

    relationship_ids = OntologyRelationship
      .where(source_node_type: "OntologyEntity", source_node_id: stale_ids)
      .or(OntologyRelationship.where(target_node_type: "OntologyEntity", target_node_id: stale_ids))
      .pluck(:id)
    OntologyRelationshipEvidence.where(ontology_relationship_id: relationship_ids).delete_all
    stale.each(&:destroy)
    @stats[:removed] = stale_ids.size
  end

  def link_concerns(situation, kind, reference)
    # :place is a concerns edge like :entity -- the place entity carries the
    # coordinate the board anchors on. Only :actor situations have no place of
    # their own.
    return unless kind == :entity || kind == :place

    entity = OntologyEntity.find_by(id: reference)
    return unless entity

    OntologySyncSupport.upsert_relationship(
      source_node: situation,
      target_node: entity,
      relation_type: CONCERNS,
      confidence: 0.8,
      derived_by: DERIVED_BY,
      explanation: "Reports grouped into this situation name #{entity.canonical_name}.",
      metadata: { "built_at" => now.iso8601 }
    )
  end

  def situation_name(kind, reference, members)
    subject = OntologyEntity.find_by(id: reference)&.canonical_name
    return "#{subject} situation" if subject.present?

    members.first.first.canonical_title.to_s.first(80)
  end

  def coherent?(cluster)
    titles = article_titles_by_cluster[cluster.id].to_a
    # A single report is not incoherent, it is just alone; it stands or falls on
    # its own key.
    return true if titles.size < 2

    sets = titles.map { |title| content_words(title) }.reject(&:empty?)
    return true if sets.size < 2

    pairs = sets.combination(2).map { |a, b| (a & b).size.to_f / (a | b).size }
    (pairs.sum / pairs.size) >= COHERENCE_FLOOR
  end

  def content_words(title)
    title.to_s.downcase.gsub(/[^a-z0-9 ]/, " ").split
      .reject { |word| word.length < 4 || STOPWORDS.include?(word) }.to_set
  end

  def clusters
    @clusters ||= NewsStoryCluster.where("last_seen_at >= ?", now - days.days).to_a
  end

  # Member headlines per cluster, loaded in two queries rather than two per
  # cluster. Capped because coherence is a mean over pairs and the first handful
  # of members settles it.
  def article_titles_by_cluster
    @article_titles_by_cluster ||= begin
      memberships = NewsStoryMembership
        .where(news_story_cluster_id: clusters.map(&:id))
        .pluck(:news_story_cluster_id, :news_article_id)
      titles = NewsArticle.where(id: memberships.map(&:last).uniq).pluck(:id, :title).to_h

      memberships.group_by(&:first).transform_values do |rows|
        rows.first(8).filter_map { |_, article_id| titles[article_id] }
      end.tap { |hash| hash.default = [] }
    end
  end

  def events_by_cluster
    @events_by_cluster ||= OntologyEvent
      .where(primary_story_cluster_id: clusters.map(&:id))
      .index_by(&:primary_story_cluster_id)
  end

  def event_ids
    @event_ids ||= events_by_cluster.values.map(&:id)
  end

  def named_entity_ids
    @named_entity_ids ||= OntologyRelationship
      .where(source_node_type: "OntologyEvent", source_node_id: event_ids,
             relation_type: NewsRegistryLinkService::RELATION_TYPE)
      .pluck(:source_node_id, :target_node_id)
      .group_by(&:first)
      .transform_values { |rows| rows.map(&:last) }
  end

  def actor_memberships
    @actor_memberships ||= OntologyEventEntity
      .joins(:ontology_entity)
      .where(ontology_event_id: event_ids, ontology_entities: { entity_type: "actor" })
      .pluck(:ontology_event_id, :ontology_entity_id)
  end

  def actor_ids_by_event
    @actor_ids_by_event ||= actor_memberships.group_by(&:first)
      .transform_values { |rows| rows.map(&:last).uniq }
      .tap { |hash| hash.default = [] }
  end

  def actor_frequency
    @actor_frequency ||= begin
      total = [event_ids.size, 1].max
      actor_memberships.map(&:last).tally.transform_values { |count| count.to_f / total }
    end
  end
end
