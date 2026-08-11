# Writes the edge that joins ring 0 to ring 3: news event -> the registry entity
# it names.
#
# The supply chain graph already knows a Hormuz closure reaches Oman, Pakistan and
# Japan via LNG -- 2,006 chokepoint exposures, 953 commodity dependencies, 138
# relationships on the Hormuz entity alone. News already produces events. Before
# this, nothing connected the two: 93 clusters about Hormuz, 0 edges to it.
#
# Only matches RegistryNameIndex reports as confident are written. The candidate
# tier is real but unresolved -- "JAZAN" names a refinery and "NAGASAKI" names a
# port, and only one of those stories is about the facility. Writing both to make
# the connectivity number look better is the failure the plan warns about:
# connectivity is gameable, and link-everything-to-everything reaches 90%.
class NewsRegistryLinkService
  # An OntologyRelationship rather than an OntologyEventEntity membership. Both
  # exist, and the choice matters: event_entities holds actor roles (initiator,
  # target, affected_party), while every event -> physical thing edge in the
  # graph is a relationship -- that is how OntologyRelationshipSyncService links
  # a thermal strike to a port, and it is the only one of the two that the
  # traversal in OntologyScorecardService#event_edges reads.
  RELATION_TYPE = "names_entity".freeze
  DERIVED_BY = "news_registry_link_v1".freeze
  CONFIDENCE = 0.9

  # A resolved candidate is a model judgement rather than a string match, so it
  # is recorded at a lower confidence than a corridor the text names outright.
  RESOLVED_CONFIDENCE = 0.75

  class << self
    def sync_recent(days: 21, now: Time.current, resolver: RegistryEntityResolver)
      new(now: now, resolver: resolver)
        .sync(NewsStoryCluster.where("last_seen_at >= ?", now - days.days))
    end

    def sync_cluster(cluster, now: Time.current, resolver: RegistryEntityResolver)
      new(now: now, resolver: resolver).sync(NewsStoryCluster.where(id: cluster.id))
    end
  end

  # resolver: nil runs the deterministic tier alone, which is what the tests of
  # that tier use and what a run without an API key falls back to.
  def initialize(now: Time.current, resolver: nil)
    @now = now
    @resolver = resolver
    @index = RegistryNameIndex.new
  end

  def sync(clusters)
    stats = Hash.new(0)

    clusters.find_each do |cluster|
      event = OntologyEvent.find_by(primary_story_cluster_id: cluster.id)
      next stats[:no_event] += 1 unless event

      found = index.match(cluster.canonical_title)
      matches = found.select(&:confident?)

      resolved = resolve_candidates(cluster, found.reject(&:confident?))
      stats[:resolved] += resolved.size
      matches += resolved

      # Runs even with nothing matched: a cluster retitled away from the thing it
      # used to name still carries the old edge, and an early return here would
      # leave it there permanently.
      written = write_edges(event, matches)

      stats[matches.empty? ? :no_match : :linked] += 1
      stats[:edges] += written
    end

    stats
  end

  private

  attr_reader :now, :index, :resolver

  # The tier string matching cannot settle. Candidates are widened to the assets
  # co-located with each match first, because a town's refinery and its port
  # carry different spellings of the same name and only one of them is reachable
  # from the text -- offered only the port, the model rightly answers none on a
  # story about the refinery.
  def resolve_candidates(cluster, candidates)
    return [] if resolver.nil? || candidates.empty?
    # A headline that names no facility of any kind is a bare place mention, and
    # asking the model to choose an asset for it only invites a wrong pick --
    # measured at ~60% precision before this gate, against 100% for the
    # deterministic tier. Cheaper than a model call, too.
    return [] unless index.facility_mentioned?(cluster.canonical_title)

    widened = (candidates + candidates.flat_map { |match| index.co_located(match) })
      .uniq(&:entity_id)

    resolution = resolver.call(title: cluster.canonical_title, candidates: widened)
    return [] unless resolution.resolved?

    widened.select { |match| match.entity_id == resolution.entity_id }
  end

  def write_edges(event, matches)
    kept = matches.map do |match|
      entity = OntologyEntity.find(match.entity_id)
      OntologySyncSupport.upsert_relationship(
        source_node: event,
        target_node: entity,
        relation_type: RELATION_TYPE,
        confidence: match.confident? ? CONFIDENCE : RESOLVED_CONFIDENCE,
        derived_by: DERIVED_BY,
        explanation: "The report names #{entity.canonical_name}.",
        metadata: {
          "surface" => match.surface,
          "entity_type" => match.entity_type,
          "linked_at" => now.iso8601,
        }
      ).id
    end

    prune_stale(event, kept)
    kept.size
  end

  # A retitled cluster names something different, and the edge it used to carry
  # is no longer supported by any text. Scoped by derived_by so the exposure and
  # disruption edges other services own on the same event are untouched.
  def prune_stale(event, kept_ids)
    stale = OntologyRelationship
      .where(source_node: event, relation_type: RELATION_TYPE, derived_by: DERIVED_BY)
      .where.not(id: kept_ids)
      .pluck(:id)
    return if stale.empty?

    OntologyRelationshipEvidence.where(ontology_relationship_id: stale).delete_all
    OntologyRelationship.where(id: stale).delete_all
  end
end
