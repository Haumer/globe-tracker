require "test_helper"

class HazardOccurrenceLinkServiceTest < ActiveSupport::TestCase
  RELATION = HazardOccurrenceLinkService::RELATION_TYPE

  # Vectors are written by hand rather than embedded, so the tests state the
  # geometry they depend on instead of depending on an API being reachable.
  def vector(*weights)
    Array.new(8) { |i| weights[i].to_f }
  end

  def report(key:, title:, event_type: "earthquake", at: 1.day.ago, vectors: [])
    cluster = NewsStoryCluster.create!(
      cluster_key: key, canonical_title: title, event_family: "disaster", event_type: event_type,
      verification_status: "single_source", geo_precision: "unknown", cluster_confidence: 0.6,
      source_reliability: 0.6, geo_confidence: 0.0, first_seen_at: at, last_seen_at: at
    )
    source = NewsSource.create!(canonical_key: "publisher:test:#{key}", name: "Test #{key}")
    vectors.each_with_index do |embedding, i|
      article = NewsArticle.create!(
        news_source: source, title: "#{title} #{i}", url: "https://example.test/#{key}/#{i}",
        canonical_url: "https://example.test/#{key}/#{i}", published_at: at, fetched_at: at,
        title_embedding: embedding, title_embedding_model: "test@8"
      )
      NewsStoryMembership.create!(news_story_cluster: cluster, news_article: article)
    end
    event = OntologyEvent.create!(
      canonical_key: "news-story-cluster:#{key}", primary_story_cluster: cluster,
      event_family: "disaster", event_type: event_type, last_seen_at: at
    )
    [cluster, event]
  end

  def occurrence(key:, title:, event_type: "earthquake", at: 2.days.ago, radius_km: 150.0, lat: 4.8, lng: -76.2)
    place = OntologyEntity.create!(
      canonical_key: "place:hazard:#{event_type}:#{key}", entity_type: "place", canonical_name: title,
      metadata: { "latitude" => lat, "longitude" => lng }
    )
    OntologyEvent.create!(
      canonical_key: "event:#{event_type}:#{key}", event_family: "disaster", event_type: event_type,
      place_entity: place, latitude: lat, longitude: lng, started_at: at, last_seen_at: at,
      metadata: { "canonical_title" => title, "radius_km" => radius_km, "severity" => "critical" }
    )
  end

  def country(name, code)
    entity = OntologyEntity.create!(canonical_key: "actor:state:#{code.downcase}", entity_type: "actor",
                                    canonical_name: name, country_code: code)
    OntologyRelationship.create!(source_node: entity, target_node: entity,
                                 relation_type: OntologyV2IdentityService::REPRESENTS_COUNTRY,
                                 confidence: 1.0, derived_by: "test")
    entity
  end

  def tag(event, entity, role: "affected_party")
    OntologyEventEntity.create!(ontology_event: event, ontology_entity: entity, role: role)
  end

  # Three tight seed reports plus one that reads like them but is typed
  # something else -- the case the whole service exists for, since the news
  # classifier put the largest Colombia cluster under `ground_operation`.
  def colombia_scene(mistyped_vector: vector(1, 1, 0, 0))
    colombia = country("Colombia", "CO")
    quake = occurrence(key: "q1", title: "5 km S of San Jose del Palmar, Colombia")

    seeds = [
      ["s1", vector(1, 0, 0, 0)],
      ["s2", vector(1, 0.4, 0, 0)],
      ["s3", vector(0.9, 0, 0.3, 0)]
    ].map do |key, embedding|
      _c, event = report(key: key, title: "Quake #{key}", vectors: [embedding])
      tag(event, colombia)
      event
    end

    _c, mistyped = report(key: "m1", title: "More than 100 killed", event_type: "ground_operation",
                          vectors: [mistyped_vector])
    tag(mistyped, colombia)

    [quake, seeds, mistyped, colombia]
  end

  test "grows past the news classifier to the report it mistyped" do
    quake, seeds, mistyped, = colombia_scene

    HazardOccurrenceLinkService.sync_recent

    place = quake.place_entity
    assert_equal (seeds.map(&:id) + [mistyped.id]).sort,
                 OntologyRelationship.where(relation_type: RELATION, target_node: place)
                   .pluck(:source_node_id).sort,
                 "the seed types the story, the embedding recalls the rest of it"
  end

  # The failure the bar exists to prevent: a report that merely shares a country
  # with the occurrence and reads nothing like it.
  test "a report that only shares the country is not admitted" do
    _quake, _seeds, _mistyped, colombia = colombia_scene

    _c, unrelated = report(key: "u1", title: "New president sworn in", event_type: "election",
                           vectors: [vector(0, 0, 0, 1)])
    tag(unrelated, colombia)

    HazardOccurrenceLinkService.sync_recent

    assert_not OntologyRelationship.exists?(relation_type: RELATION, source_node: unrelated)
  end

  # Two members give one pair, a zero deviation, and a bar equal to whatever
  # those two happened to score against each other.
  test "will not calibrate an admission bar on a single pair" do
    colombia = country("Colombia", "CO")
    occurrence(key: "q1", title: "5 km S of San Jose del Palmar, Colombia")
    [["s1", vector(1, 0, 0, 0)], ["s2", vector(1, 0.4, 0, 0)]].each do |key, embedding|
      _c, event = report(key: key, title: "Quake #{key}", vectors: [embedding])
      tag(event, colombia)
    end

    HazardOccurrenceLinkService.sync_recent

    assert_equal 0, OntologyRelationship.where(relation_type: RELATION).count
  end

  # An occurrence at sea names no country, so it can never gather a candidate
  # and must not gather one by accident.
  test "an occurrence in open water matches no country" do
    country("Colombia", "CO")
    quake = occurrence(key: "q2", title: "northern Mid-Atlantic Ridge", lat: 17.5, lng: -45.8)

    HazardOccurrenceLinkService.sync_recent

    assert_equal 0, OntologyRelationship.where(relation_type: RELATION, target_node: quake.place_entity).count
  end

  # Longest match first, or every quake in Papua New Guinea is filed under
  # Guinea.
  test "matches the longer country name inside the occurrence title" do
    country("Guinea", "GN")
    png = country("Papua New Guinea", "PG")
    quake = occurrence(key: "q3", title: "31 km SSW of Ialibu, Papua New Guinea", lat: -6.3, lng: 143.9)
    [["s1", vector(1, 0, 0, 0)], ["s2", vector(1, 0.4, 0, 0)], ["s3", vector(0.9, 0, 0.3, 0)]]
      .each do |key, embedding|
        _c, event = report(key: key, title: "Quake #{key}", vectors: [embedding])
        tag(event, png)
      end

    HazardOccurrenceLinkService.sync_recent

    assert_equal 3, OntologyRelationship.where(relation_type: RELATION, target_node: quake.place_entity).count
  end

  # A mainshock and its aftershock admit the same coverage. Time proximity hands
  # the story to the aftershock; magnitude-derived reach hands it to the event
  # the coverage is actually about.
  test "the larger footprint claims reports away from its aftershock" do
    _quake, _seeds, _mistyped, = colombia_scene
    aftershock = occurrence(key: "q9", title: "16 km W of San Jose del Palmar, Colombia",
                            at: 1.5.days.ago, radius_km: 90.0)

    HazardOccurrenceLinkService.sync_recent

    assert_equal 0, OntologyRelationship.where(relation_type: RELATION, target_node: aftershock.place_entity).count
    assert_equal 4, OntologyRelationship.where(relation_type: RELATION).count
  end

  # The occurrence knows how far it reached; the place entity standing in for it
  # on the globe does not until this runs.
  test "carries the measured footprint onto the place entity" do
    quake, = colombia_scene
    assert_nil quake.place_entity.metadata["radius_km"]

    HazardOccurrenceLinkService.sync_recent

    assert_equal 150.0, quake.place_entity.reload.metadata["radius_km"]
    assert_equal "critical", quake.place_entity.metadata["severity"]
  end

  # A report cannot describe an occurrence that has not happened yet, so it
  # cannot be part of the sample that decides what the occurrence reads like.
  test "a report filed before the occurrence cannot seed it" do
    colombia = country("Colombia", "CO")
    occurrence(key: "q1", title: "5 km S of San Jose del Palmar, Colombia", at: 1.day.ago)
    [["s1", vector(1, 0, 0, 0)], ["s2", vector(1, 0.4, 0, 0)], ["s3", vector(0.9, 0, 0.3, 0)]]
      .each do |key, embedding|
        _c, event = report(key: key, title: "Quake #{key}", at: 5.days.ago, vectors: [embedding])
        tag(event, colombia)
      end

    HazardOccurrenceLinkService.sync_recent

    assert_equal 0, OntologyRelationship.where(relation_type: RELATION).count
  end

  # Both roles point at Colombia on the same report. Counted twice, the report
  # deflates the spread the bar is measured from.
  test "a report tagged with the same country twice counts once" do
    _quake, seeds, = colombia_scene
    tag(seeds.first, OntologyEntity.find_by(canonical_key: "actor:state:co"), role: "initiator")

    HazardOccurrenceLinkService.sync_recent

    assert_equal 1, OntologyRelationship.where(relation_type: RELATION, source_node: seeds.first).count
  end
end
