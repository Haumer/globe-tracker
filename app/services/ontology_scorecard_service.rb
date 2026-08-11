# Scores the ontology against a fixed set of metrics so a rework is a diff
# against a number rather than an impression.
#
# Two prior approaches to this graph exist (`ontology_relationship_sync_v1` and
# the `ontology_v2_*` family) and neither can be compared to the other, because
# neither was ever baselined. That is the gap this closes.
#
# Metrics 1-3 are individually gameable -- link every event to every asset in
# its country and connectivity reaches 90% -- so `anchor_precision` is reported
# alongside them and never separately. An approach that raises coverage while
# anchor precision falls is worse, not better.
class OntologyScorecardService
  # Entity types that mean "news talking about itself". An event linked only to
  # these is not connected to the world in any useful sense.
  NEWS_ENTITY_TYPES = %w[source actor place].freeze

  # The precision tiers at which `geocode_place_name` is a place rather than a
  # masthead or a bare country code. Mirrors Api::NewsController::LOCATED_PRECISIONS.
  LOCATED_PRECISIONS = %w[city place region airport].freeze

  # Umbrella labels that are continents or catch-alls rather than a real
  # situation. ConflictPulseService falls back to these when its hand-written
  # NAMED_THEATERS table has no entry, which is the failure this measures.
  GENERIC_THEATERS = %w[
    Global Africa Europe Americas Oceania
  ].push("East Asia", "South Asia", "Southeast Asia", "Russia & Central Asia").freeze

  # Same-type events this close together in space and time are probably one
  # real-world event that failed to merge.
  FRAGMENT_RADIUS_KM = 100.0
  FRAGMENT_WINDOW = 24.hours

  Result = Struct.new(:metrics, :window, :generated_at, keyword_init: true) do
    def to_h = { window: window, generated_at: generated_at, metrics: metrics }
  end

  def self.call(...) = new(...).call

  def initialize(since: 30.days.ago, now: Time.current)
    @since = since
    @now = now
  end

  def call
    Result.new(
      window: { since: @since, until: @now },
      generated_at: @now,
      metrics: {
        ingest_yield: ingest_yield,
        cross_domain_link_rate: cross_domain_link_rate,
        situation_coverage: situation_coverage,
        anchor_precision: anchor_precision,
        fragmentation: fragmentation,
        liveness: liveness,
      }
    )
  end

  private

  attr_reader :since, :now

  def metric(value, total, extra = {})
    {
      value: total.to_i.zero? ? 0.0 : (100.0 * value / total).round(1),
      count: value,
      total: total,
    }.merge(extra)
  end

  # 1. Does data get in at all? Counted end to end, because each stage's
  # survival rate flatters itself by ignoring what the previous stage dropped.
  def ingest_yield
    articles = NewsArticle.where(fetched_at: since..now).count
    in_scope = NewsArticle.where(fetched_at: since..now)
      .where.not(content_scope: "out_of_scope").count
    claims = NewsClaim.joins(:news_article)
      .where(news_articles: { fetched_at: since..now }).count
    clusterable = NewsClaim.joins(:news_article)
      .where(news_articles: { fetched_at: since..now })
      .where(event_family: NewsStoryClusterer::CLUSTERABLE_EVENT_FAMILIES.to_a)
      .where.not(event_type: NewsStoryClusterer::GENERAL_EVENT_TYPES)
      .count

    metric(clusterable, articles,
      stages: {
        articles: articles,
        survived_scope: in_scope,
        produced_claim: claims,
        clusterable: clusterable,
      })
  end

  # 2. The headline. An ontology whose events only reach news actors and news
  # places has not connected anything to anything.
  def cross_domain_link_rate
    events = OntologyEvent.where(last_seen_at: since..now).pluck(:id)
    return metric(0, 0, by_target: {}) if events.empty?

    entity_types = OntologyEntity.pluck(:id, :entity_type).to_h
    edges = event_edges(events)

    cross = events.count do |id|
      Array(edges[id]).any? do |target_type, target_id|
        target_type == "OntologyEntity" && !NEWS_ENTITY_TYPES.include?(entity_types[target_id])
      end
    end

    by_target = edges.values.flatten(1).filter_map do |target_type, target_id|
      target_type == "OntologyEntity" ? entity_types[target_id] : target_type
    end.tally.sort_by { -_2 }.to_h

    metric(cross, events.size, by_target: by_target)
  end

  # 3. Is "the Iran war" a thing? A conflict assigned to "Americas" has an
  # umbrella in name only.
  def situation_coverage
    clusters = conflict_clusters
    return metric(0, 0, by_theater: {}) if clusters.empty?

    theaters = clusters.map do |_id, lat, lng, title, place|
      situation = ConflictPulseService.infer_situation_name(
        lat: lat, lng: lng, text: [ title, place ].compact.join(" ")
      )
      ConflictPulseService.infer_theater(lat: lat, lng: lng, situation_name: situation)
    end

    named = theaters.count { |theater| !GENERIC_THEATERS.include?(theater) }
    metric(named, theaters.size, by_theater: theaters.tally.sort_by { -_2 }.to_h)
  end

  # 4. The guard on every metric above. A "place" that is really a masthead
  # makes an event's location a lie, and anything derived from it inherits that.
  def anchor_precision
    anchors = OntologyEvent.where(last_seen_at: since..now)
      .where.not(place_entity_id: nil)
      .pluck(:place_entity_id)
    return metric(0, 0) if anchors.empty?

    publishers = publisher_names
    names = OntologyEntity.where(id: anchors.uniq).pluck(:id, :canonical_name).to_h
    good = anchors.count do |id|
      name = names[id]
      name.present? && !publishers.include?(normalize(name))
    end

    metric(good, anchors.size)
  end

  # 5. Do we over-split? Reported as a soft signal: the proxy cannot separate
  # a clustering failure from a taxonomy too coarse to tell two events apart
  # (1,018 events share the type `ground_operation`). Only a labelled gold set
  # settles that, which is why this is never used alone as a pass/fail.
  def fragmentation
    clusters = NewsStoryCluster.where(last_seen_at: since..now)
      .where.not(latitude: nil, longitude: nil)
      .pluck(:id, :event_type, :latitude, :longitude, :first_seen_at)
    return metric(0, 0, confidence: "proxy") if clusters.empty?

    groups = []
    clusters.each do |id, type, lat, lng, seen_at|
      match = groups.find do |group|
        group[:type] == type &&
          (group[:seen_at] - seen_at).abs < FRAGMENT_WINDOW &&
          haversine_km(group[:lat], group[:lng], lat, lng) < FRAGMENT_RADIUS_KM
      end
      match ? match[:members] << id : groups << { type: type, lat: lat, lng: lng, seen_at: seen_at, members: [ id ] }
    end

    redundant = groups.sum { |group| group[:members].size - 1 }
    metric(redundant, clusters.size, distinct_events: groups.size, confidence: "proxy")
  end

  # 6. Is it even running? A derivation frozen months ago scores well on every
  # metric above simply because its rows are still sitting there.
  def liveness
    OntologyRelationship.group(:derived_by)
      .pluck(Arel.sql("derived_by, COUNT(*), MAX(updated_at)"))
      .each_with_object({}) do |(derived_by, count, newest), memo|
        memo[derived_by] = {
          count: count,
          age_hours: newest ? ((now - newest) / 3600.0).round(1) : nil,
        }
      end
  end

  def conflict_clusters
    NewsStoryCluster.where(event_family: "conflict")
      .where(last_seen_at: since..now)
      .where.not(latitude: nil, longitude: nil)
      .pluck(:id, :latitude, :longitude, :canonical_title, :location_name)
  end

  def event_edges(event_ids)
    ids = event_ids.to_set
    outgoing = OntologyRelationship.where(source_node_type: "OntologyEvent", source_node_id: event_ids)
      .pluck(:source_node_id, :target_node_type, :target_node_id)
    incoming = OntologyRelationship.where(target_node_type: "OntologyEvent", target_node_id: event_ids)
      .pluck(:target_node_id, :source_node_type, :source_node_id)

    (outgoing + incoming).each_with_object({}) do |(event_id, other_type, other_id), memo|
      next unless ids.include?(event_id)

      (memo[event_id] ||= []) << [ other_type, other_id ]
    end
  end

  # Built from the data rather than a hardcoded list, so it stays true as feeds
  # are added.
  #
  # Drawn from the publisher columns only. An earlier version also folded in
  # NewsEvent#name on the reasoning that it is where the publisher leaks in --
  # but that column is mixed, holding real place names as often as mastheads, so
  # including it marked legitimate anchors like "Milwaukee" as publishers and
  # overstated the defect by roughly 2.5x. Measure the disease with a clean
  # instrument or the cure looks better than it is.
  def publisher_names
    @publisher_names ||= begin
      names = NewsSource.pluck(:name) + NewsArticle.distinct.pluck(:publisher_name)
      names.compact.map { |name| normalize(name) }.reject(&:blank?).to_set
    end
  end

  def normalize(value) = value.to_s.downcase.strip

  def haversine_km(lat_a, lng_a, lat_b, lng_b)
    radius = 6371.0
    d_lat = (lat_b - lat_a) * Math::PI / 180
    d_lng = (lng_b - lng_a) * Math::PI / 180
    a = (Math.sin(d_lat / 2)**2) +
        (Math.cos(lat_a * Math::PI / 180) * Math.cos(lat_b * Math::PI / 180) * (Math.sin(d_lng / 2)**2))
    2 * radius * Math.asin(Math.sqrt(a))
  end
end
