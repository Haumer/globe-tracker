# Joins news to the second registry the graph already holds: sensor-observed
# occurrences.
#
# NewsRegistryLinkService answers "what standing thing does this report name?"
# against ports, corridors, refineries and bases. Nothing answered "what
# *happening* does this report describe?", even though 720 occurrences a window
# arrive from USGS, FIRMS and the outage feeds -- each already an OntologyEvent
# with a point, an onset and its own footprint, and each already carrying a
# place:hazard:* entity. Edges from news to any of them: 0. That is why the
# 7.4 that killed 111 people in Colombia produced no situation while a Hormuz
# headline produced one.
#
# The join deliberately is NOT geometric. News coordinates cannot carry it: 750
# of 2,192 geo-coded news events in a window sit on eight capital points, the
# Colombia reports sit on Bogota 257km from a 202km epicentre footprint, and the
# place entity behind one of them is literally named "Reuters" at Moscow's
# coordinates. Matching those points against a measured radius yields 26 hits a
# window, of which "Apple Pay now in Philippines" inside an earthquake is
# representative. So this matches on what the two sides can both be trusted
# about: the country, the onset, and the meaning of the headline.
class HazardOccurrenceLinkService
  # Not names_entity. A report does not *name* place:hazard:earthquake:us6000tjl2
  # -- it describes the occurrence that record measures. Reusing names_entity
  # would have let this key situations with no change to SituationBuilder at all,
  # and that is exactly why it is wrong: the scorecard's connectivity metric
  # reads that edge, and a differently-derived claim would inflate it without any
  # report having reached a physical thing by name.
  RELATION_TYPE = "reports_occurrence".freeze
  DERIVED_BY = "hazard_occurrence_link_v1".freeze
  OCCURRENCE_KEY_PREFIX = "event:".freeze

  # The seed is not just the story's core, it is the sample the admission bar is
  # measured from -- and a spread over a single pair is not a measurement. Two
  # members give one pair, a zero deviation, and a bar equal to whatever those
  # two happened to score: that is how a 6.8 off Japan admitted "Okinawa airport
  # suspends operations ahead of Typhoon", which was no further from the seed
  # than the seed's own members were from each other. Three members give three
  # pairs and a spread that means something.
  MINIMUM_SEED = 3

  class << self
    def sync_recent(days: 21, now: Time.current)
      new(days: days, now: now).call
    end
  end

  def initialize(days: 21, now: Time.current)
    @days = days
    @now = now
    @stats = Hash.new(0)
  end

  # Each news event is claimed by at most one occurrence. Two quakes in one
  # country in one window would otherwise both claim the same reports and split
  # the story in half, which is the fragmentation this whole layer exists to
  # undo.
  #
  # The winner is the one that reaches furthest, not the one that landed nearest
  # in time. A mainshock and its aftershock both admit the same coverage, and
  # time proximity hands the story to the aftershock -- the Colombia reports
  # anchored on a medium 150km event 45 minutes after the critical 202km one
  # that actually killed 111 people. The footprint is derived from magnitude, so
  # the largest is the occurrence the coverage is about.
  def call
    claims = {}

    occurrences.each do |occurrence|
      @stats[:occurrences] += 1
      admitted = admitted_events(occurrence)
      next @stats[:no_group] += 1 if admitted.empty?

      @stats[:grouped] += 1
      admitted.each do |event|
        current = claims[event.id]
        claims[event.id] = occurrence if current.nil? || better?(occurrence, current, event)
      end
    end

    write(claims)
    @stats
  end

  private

  attr_reader :days, :now

  def better?(candidate, incumbent, event)
    reach = reach_of(candidate) <=> reach_of(incumbent)
    return reach.positive? unless reach.zero?

    time_gap(event, candidate) < time_gap(event, incumbent)
  end

  def reach_of(occurrence)
    occurrence.metadata["radius_km"].to_f
  end

  def write(claims)
    by_occurrence = claims.group_by { |_, occurrence| occurrence }

    by_occurrence.each do |occurrence, rows|
      place = place_entities[occurrence.place_entity_id]
      next unless place

      # The occurrence knows how far it reached; the place entity standing in for
      # it does not. Carrying the radius across is what lets the globe draw the
      # measured footprint instead of falling back to a nominal one.
      enrich(place, occurrence)

      rows.each do |event_id, _|
        OntologySyncSupport.upsert_relationship(
          source_node: events_by_id[event_id],
          target_node: place,
          relation_type: RELATION_TYPE,
          confidence: 0.75,
          derived_by: DERIVED_BY,
          explanation: "Reported alongside #{occurrence.metadata['canonical_title']} " \
                       "(#{occurrence.event_type}, #{occurrence.started_at&.to_date}).",
          metadata: { "occurrence_key" => occurrence.canonical_key, "built_at" => now.iso8601 }
        )
        @stats[:edges] += 1
      end
    end
  end

  def enrich(place, occurrence)
    carried = occurrence.metadata.slice("radius_km", "severity", "canonical_title", "event_kind")
    return if carried.empty? || carried.all? { |key, value| place.metadata[key] == value }

    place.update!(metadata: place.metadata.merge(carried))
  end

  def time_gap(event, occurrence)
    (event.last_seen_at.to_i - occurrence.started_at.to_i).abs
  end

  # ── membership ──────────────────────────────────────────────────────

  # Seed on exact agreement, then grow on meaning.
  #
  # The seed is high precision and low recall by construction: a report typed
  # `earthquake`, carrying the occurrence's country, published no earlier than
  # the occurrence, is about it. That caught 5 of the 15 Colombia reports. The
  # other 10 include both 62-article clusters, one of which the news classifier
  # typed `ground_operation` -- the same quake also produced `airstrike` and
  # `explosion`. Recall has to come from somewhere the classifier is not.
  def admitted_events(occurrence)
    country_id = country_actor_for(occurrence)
    return [] unless country_id

    candidates = candidates_for(country_id)
    seed = seed_from(candidates, occurrence)
    return [] if seed.size < MINIMUM_SEED

    vectors = seed.filter_map { |event| cluster_vectors[event.primary_story_cluster_id] }
    return [] if vectors.size < MINIMUM_SEED

    bar = admission_bar(vectors)
    return [] unless bar

    grown = candidates.select do |event|
      vector = cluster_vectors[event.primary_story_cluster_id]
      vector && vectors.any? { |member| cosine(vector, member) >= bar }
    end

    (seed | grown)
  end

  # The bar is the seed's own internal spread, recomputed for every occurrence.
  # No corpus-wide cosine floor is chosen here: a tight seed admits only its own
  # kind, a loose one is allowed to reach further, and the measurement that sets
  # the threshold is the story's own coherence rather than a number tuned once
  # against one window. Mean minus a standard deviation over the seed's pairs,
  # applied as single linkage, measured on the Colombia occurrence at 10 of 15
  # true reports with no false admission that was not already a mixed cluster.
  def admission_bar(vectors)
    pairs = vectors.combination(2).map { |left, right| cosine(left, right) }
    return if pairs.empty?

    mean = pairs.sum / pairs.size
    deviation = Math.sqrt(pairs.sum { |value| (value - mean)**2 } / pairs.size)
    mean - deviation
  end

  # A report cannot describe an occurrence that has not happened yet. This is the
  # only time bound applied, and it is a physical constraint rather than a tuned
  # window -- the candidates are already bounded by the caller's window.
  def seed_from(candidates, occurrence)
    candidates.select do |event|
      event.event_type == occurrence.event_type &&
        event.last_seen_at.present? &&
        occurrence.started_at.present? &&
        event.last_seen_at >= occurrence.started_at
    end
  end

  def candidates_for(country_id)
    news_events_by_country[country_id].to_a
  end

  def cosine(left, right)
    NewsHeadlineEmbeddingService.cosine(left, right)
  end

  # ── the country the occurrence sits in ──────────────────────────────

  # None of the 159,989 hazard places carry a country_code, but every occurrence
  # carries the describing string its sensor wrote -- "5 km S of San Jose del
  # Palmar, Colombia". That string is matched against the country actors already
  # in the graph, the same way RegistryNameIndex matches a headline against
  # registry names. Longest match wins so "Papua New Guinea" is not read as
  # "Guinea", and an occurrence at sea ("northern Mid-Atlantic Ridge") matches
  # nothing and is correctly dropped.
  def country_actor_for(occurrence)
    title = occurrence.metadata["canonical_title"].to_s
    return if title.blank?

    country_actors.find { |_, name| title.match?(/(?<![[:alnum:]])#{Regexp.escape(name)}(?![[:alnum:]])/i) }&.first
  end

  def country_actors
    @country_actors ||= OntologyEntity
      .where(entity_type: "actor", id: country_actor_ids)
      .where.not(canonical_name: nil)
      .pluck(:id, :canonical_name)
      .sort_by { |_, name| -name.length }
  end

  def country_actor_ids
    @country_actor_ids ||= OntologyRelationship
      .where(relation_type: OntologyV2IdentityService::REPRESENTS_COUNTRY,
             source_node_type: "OntologyEntity")
      .distinct.pluck(:source_node_id)
  end

  # ── loading ─────────────────────────────────────────────────────────

  def window_start
    @window_start ||= now - days.days
  end

  def occurrences
    @occurrences ||= OntologyEvent
      .where("canonical_key LIKE ?", "#{OCCURRENCE_KEY_PREFIX}%")
      .where("last_seen_at >= ?", window_start)
      .where.not(place_entity_id: nil)
      .where.not(started_at: nil)
      .order(:started_at).to_a
  end

  def place_entities
    @place_entities ||= OntologyEntity
      .where(id: occurrences.map(&:place_entity_id).uniq).index_by(&:id)
  end

  def news_events
    @news_events ||= OntologyEvent
      .where("canonical_key LIKE ?", "news-story-cluster:%")
      .where("last_seen_at >= ?", window_start)
      .where.not(primary_story_cluster_id: nil).to_a
  end

  def events_by_id
    @events_by_id ||= news_events.index_by(&:id)
  end

  def news_events_by_country
    @news_events_by_country ||= begin
      rows = OntologyEventEntity
        .where(ontology_event_id: news_events.map(&:id), ontology_entity_id: country_actor_ids)
        .pluck(:ontology_entity_id, :ontology_event_id)

      # uniq because an event carries a country actor once per role -- initiator
      # and affected_party both point at Colombia on the same report. Without it
      # the report is counted twice in the seed, which deflates the spread the
      # admission bar is measured from.
      rows.group_by(&:first)
        .transform_values { |pairs| pairs.map(&:last).uniq.filter_map { |id| events_by_id[id] } }
        .tap { |hash| hash.default = [] }
    end
  end

  # One vector per cluster, the mean of its members' headline embeddings. Not
  # every article has one -- coverage is partial and a cluster with none simply
  # cannot be grown into, which costs recall rather than precision.
  def cluster_vectors
    @cluster_vectors ||= begin
      cluster_ids = news_events.map(&:primary_story_cluster_id).uniq
      memberships = NewsStoryMembership.where(news_story_cluster_id: cluster_ids)
        .pluck(:news_story_cluster_id, :news_article_id)
      embeddings = NewsArticle.where(id: memberships.map(&:last).uniq)
        .where.not(title_embedding: nil).pluck(:id, :title_embedding).to_h

      memberships.group_by(&:first).each_with_object({}) do |(cluster_id, rows), out|
        vectors = rows.filter_map { |_, article_id| embeddings[article_id] }
        next if vectors.empty?

        width = vectors.first.size
        out[cluster_id] = Array.new(width) { |i| vectors.sum { |v| v[i] } / vectors.size.to_f }
      end
    end
  end
end
