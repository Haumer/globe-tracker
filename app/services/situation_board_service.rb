# The read side of SituationBuilder: everything the globe needs to draw a
# situation, in one payload.
#
# The shape is deliberately a convergence rather than an area. A situation is
# reports scattered across the world collapsing onto one anchor, and -- when the
# anchor is a registry entity -- exposure fanning back out to the countries that
# depend on it. Nothing here invents geometry: every coordinate emitted is one
# somebody measured. See #anchor_for for the single derived case and how it is
# labelled.
class SituationBoardService
  ENTITY_TYPE = SituationBuilder::ENTITY_TYPE
  MEMBERSHIP_ROLE = SituationBuilder::MEMBERSHIP_ROLE
  CONCERNS = SituationBuilder::CONCERNS

  # Ring 3 for Hormuz is 69 countries. Drawing 69 arcs from one anchor is a
  # starburst nobody can read, so the globe takes the heaviest exposures and the
  # panel carries the full count.
  RING_LIMIT = 12

  # The rings the graph already holds, kept apart rather than flattened into one
  # "exposure" list. They are different claims at different distances and only
  # two of the three are drawable: ring 1 assets and ring 3 countries have
  # coordinates, commodities do not. Flattening them also sorts wrong -- a
  # commodity flow scores 0.9 against a country exposure's 0.12, so a merged
  # top-12 is all commodities and no countries.
  RINGS = {
    ring1_assets: "downstream_exposure",
    ring2_commodities: "flow_dependency",
    ring3_countries: "chokepoint_exposure"
  }.freeze

  # Display tiering. The builder's MINIMUM_MEMBERS = 2 admits a pair of
  # single-article, single-source clusters -- two lone mentions wearing a
  # situation's clothes -- and until now the board rendered that with the same
  # standing as a 600-report story. Weak situations still ship (this is an
  # early-warning surface, and the first two reports of a coup are exactly what
  # must not be hidden); they are tiered "emerging" so the UI leads with
  # corroborated stories instead of hiding thin ones.
  #
  # Both floors must hold. Five articles from one newsroom is a beat, not
  # corroboration; three newsrooms with one report each is barely more. Sources
  # are counted distinct across the whole situation -- the same wire in three
  # clusters is one source, which the per-cluster counts cannot see.
  CORROBORATED_MIN_ARTICLES = 5
  CORROBORATED_MIN_SOURCES = 3

  def self.call(days: SituationBuilder::WINDOW_DAYS, now: Time.current)
    new(days: days, now: now).call
  end

  def initialize(days: SituationBuilder::WINDOW_DAYS, now: Time.current)
    @days = days
    @now = now
  end

  def call
    {
      generated_at: now.iso8601,
      window_days: days,
      situations: situations.map { |situation| present(situation) }.compact
        .sort_by { |row| [ row[:tier] == "corroborated" ? 0 : 1, -row[:member_count] ] }
    }
  end

  private

  attr_reader :days, :now

  def situations
    @situations ||= OntologyEntity.where(entity_type: ENTITY_TYPE).to_a
  end

  def present(situation)
    members = members_for(situation)
    return if members.empty?

    anchor = anchor_for(situation, members)
    return unless anchor

    concerns = concerns_entity(situation)
    article_count = members.sum { |member| member[:article_count].to_i }
    source_count = distinct_source_count(members)

    {
      id: situation.id,
      key: situation.canonical_key,
      name: display_name(situation),
      grouped_by: situation.metadata["grouped_by"],
      anchor: anchor,
      member_count: members.size,
      # member_count counts clusters, one per member. A cluster is several
      # reports of one story, so the two are not interchangeable and the caller
      # was previously labelling 78 clusters as 78 reports.
      article_count: article_count,
      source_count: source_count,
      tier: tier_for(article_count, source_count),
      geo_member_count: members.count { |member| member[:lat] },
      first_seen_at: members.filter_map { |m| m[:last_seen_at] }.min,
      last_seen_at: members.filter_map { |m| m[:last_seen_at] }.max,
      members: members,
      daily: daily_counts(members),
      concerns: concerns && {
        id: concerns.id,
        name: concerns.canonical_name,
        entity_type: concerns.entity_type,
        country_code: concerns.country_code,
        # Corridors carry a surveyed radius; facilities do not. Passed through
        # rather than defaulted, so the globe can tell a measured footprint from
        # one it had to nominate.
        radius_km: concerns.metadata["radius_km"]&.to_f,
        description: concerns.metadata["description"]
      },
      rings: concerns ? rings_for(concerns) : empty_rings
    }
  end

  def empty_rings
    RINGS.keys.index_with { |ring| { total: 0, shown: [] } }
  end

  # "Strait of Hormuz situation" is what the builder stores; on a globe the word
  # is redundant with the layer itself.
  def display_name(situation)
    situation.canonical_name.to_s.sub(/\s+situation\z/i, "")
  end

  def members_for(situation)
    events = member_events[situation.id].to_a
    clusters = clusters_by_id

    events.map do |event|
      cluster = clusters[event.primary_story_cluster_id]
      counts = counts_by_cluster[event.primary_story_cluster_id]

      {
        event_id: event.id,
        cluster_id: event.primary_story_cluster_id,
        headline: headline_for(cluster),
        article_count: counts[:articles],
        source_count: counts[:sources],
        event_type: event.event_type,
        event_family: event.event_family,
        lat: event.latitude,
        lng: event.longitude,
        last_seen_at: event.last_seen_at&.iso8601
      }
    end.sort_by { |member| member[:last_seen_at].to_s }.reverse
  end

  # The one derived coordinate in the payload, and it is flagged as such so the
  # globe can draw it differently.
  #
  # An entity-keyed situation sits on the registry entity it names -- a measured
  # point. An actor-keyed one has no place at all: there is no location of "the
  # European Union situation". Rather than average the members into a centroid
  # that sits in open ocean, it takes the medoid, the member report nearest all
  # the others. That is still a real anchor somebody geocoded, and the caller is
  # told which of the two it got.
  def anchor_for(situation, members)
    entity = concerns_entity(situation)
    lat, lng = coordinates(entity)

    if lat && lng
      return { lat: lat, lng: lng, kind: "registry", label: entity.canonical_name,
               entity_type: entity.entity_type }
    end

    medoid = medoid_of(members)
    return unless medoid

    { lat: medoid[:lat], lng: medoid[:lng], kind: "medoid", label: display_name(situation),
      entity_type: nil }
  end

  def medoid_of(members)
    located = members.select { |member| member[:lat] && member[:lng] }
    return if located.empty?
    return located.first if located.size == 1

    located.min_by do |candidate|
      located.sum { |other| haversine_km(candidate, other) }
    end
  end

  def haversine_km(a, b)
    rad = Math::PI / 180
    dlat = (b[:lat] - a[:lat]) * rad
    dlng = (b[:lng] - a[:lng]) * rad
    h = Math.sin(dlat / 2)**2 +
      Math.cos(a[:lat] * rad) * Math.cos(b[:lat] * rad) * Math.sin(dlng / 2)**2
    6371 * 2 * Math.asin(Math.sqrt([h, 1.0].min))
  end

  def coordinates(entity)
    return [nil, nil] unless entity

    [entity.metadata["latitude"]&.to_f, entity.metadata["longitude"]&.to_f]
  end

  def daily_counts(members)
    stamps = members.filter_map { |member| member[:last_seen_at] && Date.parse(member[:last_seen_at]) }
    return [] if stamps.empty?

    span = (now.to_date - (days - 1)).upto(now.to_date).to_a
    tally = stamps.tally
    span.map { |day| { date: day.iso8601, count: tally[day].to_i } }
  end

  def rings_for(entity)
    RINGS.transform_values { |relation_type| ring(entity, relation_type) }
  end

  def ring(entity, relation_type)
    rows = exposure_relations(entity).select { |r| r.relation_type == relation_type }
      .filter_map { |relation| exposure_row(relation) }
      .sort_by { |row| -row[:score].to_f }

    { total: rows.size, shown: rows.first(RING_LIMIT) }
  end

  def exposure_row(relation)
    target = exposure_targets[relation.target_node_id]
    return unless target

    lat, lng = coordinates(target)

    {
      id: target.id,
      name: target.canonical_name,
      entity_type: target.entity_type,
      country_code: target.country_code,
      lat: lat,
      lng: lng,
      # chokepoint_exposure scores the country, flow_dependency carries a share
      # of the corridor's throughput, and downstream_exposure only has the
      # relationship's own confidence. Ranking happens inside a ring, never
      # across them, so the three are not being compared to each other.
      score: relation.metadata["max_exposure_score"]&.to_f ||
        relation.metadata["flow_pct"]&.to_f&./(100) ||
        relation.confidence,
      distance_km: relation.metadata["distance_km"]&.to_f,
      commodities: Array(relation.metadata["commodities"])
    }
  end

  def exposure_relations(entity)
    all_exposure_relations[entity.id].to_a
  end

  def all_exposure_relations
    @all_exposure_relations ||= OntologyRelationship
      .where(source_node_type: "OntologyEntity", source_node_id: concerns_entities.keys,
             relation_type: RINGS.values)
      .group_by(&:source_node_id)
      .tap { |hash| hash.default = [] }
  end

  def exposure_targets
    @exposure_targets ||= OntologyEntity
      .where(id: all_exposure_relations.values.flatten.map(&:target_node_id).uniq)
      .index_by(&:id)
  end

  def concerns_entity(situation)
    concerns_entities[concerns_by_situation[situation.id]]
  end

  def concerns_by_situation
    @concerns_by_situation ||= OntologyRelationship
      .where(source_node_type: "OntologyEntity", source_node_id: situations.map(&:id),
             relation_type: CONCERNS)
      .pluck(:source_node_id, :target_node_id).to_h
  end

  def concerns_entities
    @concerns_entities ||= OntologyEntity
      .where(id: concerns_by_situation.values.uniq).index_by(&:id)
  end

  def memberships
    @memberships ||= OntologyEventEntity
      .where(ontology_entity_id: situations.map(&:id), role: MEMBERSHIP_ROLE)
      .pluck(:ontology_entity_id, :ontology_event_id)
  end

  def member_events
    @member_events ||= begin
      events = OntologyEvent.where(id: memberships.map(&:last).uniq).index_by(&:id)
      memberships.group_by(&:first)
        .transform_values { |rows| rows.filter_map { |_, event_id| events[event_id] } }
        .tap { |hash| hash.default = [] }
    end
  end

  def clusters_by_id
    @clusters_by_id ||= NewsStoryCluster.where(id: cluster_ids).index_by(&:id)
  end

  def cluster_ids
    @cluster_ids ||= member_events.values.flatten.map(&:primary_story_cluster_id).compact.uniq
  end

  # canonical_title is the lead member's headline as the feed published it, so
  # it carries a trailing " - Publisher" on about one row in six. The same
  # suffix is why "Bangkok Post" once resolved to the port of BANGKOK, which is
  # what RegistryNameIndex.strip_publisher was written for; the panel just never
  # called it. One pass, so "... restored - Reuters - tass.com" keeps Reuters
  # and loses the domain -- stripping repeatedly starts eating real titles that
  # end in a dash.
  def headline_for(cluster)
    return if cluster.nil?

    RegistryNameIndex.strip_publisher(cluster.canonical_title).presence ||
      cluster.canonical_title
  end

  # article_count and source_count are denormalised columns and both drift: on
  # the clone 474 of 2,249 clusters disagree with their own memberships about
  # articles and 428 about sources. A cluster built before its news event exists
  # is stranded at zero and nothing recounts it -- four ingest services carry a
  # comment saying so. Counting the memberships is one extra query and cannot be
  # stale.
  def tier_for(article_count, source_count)
    article_count >= CORROBORATED_MIN_ARTICLES && source_count >= CORROBORATED_MIN_SOURCES ? "corroborated" : "emerging"
  end

  def distinct_source_count(members)
    members.filter_map { |member| member[:cluster_id] }
      .flat_map { |cluster_id| source_ids_by_cluster[cluster_id] }
      .uniq.size
  end

  def source_ids_by_cluster
    @source_ids_by_cluster ||= NewsStoryMembership
      .where(news_story_cluster_id: cluster_ids)
      .joins(:news_article)
      .distinct
      .pluck(:news_story_cluster_id, Arel.sql("news_articles.news_source_id"))
      .group_by(&:first)
      .transform_values { |rows| rows.filter_map(&:last) }
      .tap { |hash| hash.default = [] }
  end

  def counts_by_cluster
    @counts_by_cluster ||= NewsStoryMembership
      .where(news_story_cluster_id: cluster_ids)
      .joins(:news_article)
      .group(:news_story_cluster_id)
      .pluck(
        Arel.sql("news_story_memberships.news_story_cluster_id"),
        Arel.sql("COUNT(*)"),
        Arel.sql("COUNT(DISTINCT news_articles.news_source_id)")
      )
      .to_h { |id, articles, sources| [ id, { articles: articles, sources: sources } ] }
      .tap { |counts| counts.default = { articles: 0, sources: 0 } }
  end
end
