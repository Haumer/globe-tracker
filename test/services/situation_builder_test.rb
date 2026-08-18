require "test_helper"

class SituationBuilderTest < ActiveSupport::TestCase
  def cluster(key:, title:, article_titles: [])
    record = NewsStoryCluster.create!(
      cluster_key: key, canonical_title: title, event_family: "conflict", event_type: "airstrike",
      verification_status: "single_source", geo_precision: "unknown", cluster_confidence: 0.6,
      source_reliability: 0.6, geo_confidence: 0.0, first_seen_at: 2.days.ago, last_seen_at: 1.day.ago
    )
    source = NewsSource.create!(canonical_key: "publisher:test:#{key}", name: "Test #{key}")
    article_titles.each_with_index do |article_title, i|
      article = NewsArticle.create!(
        news_source: source, title: article_title, url: "https://example.test/#{key}/#{i}",
        canonical_url: "https://example.test/#{key}/#{i}", published_at: 1.day.ago, fetched_at: 1.day.ago
      )
      NewsStoryMembership.create!(news_story_cluster: record, news_article: article)
    end
    event = OntologyEvent.create!(
      canonical_key: "news-story-cluster:#{key}", primary_story_cluster: record,
      event_family: "conflict", event_type: "airstrike", last_seen_at: 1.day.ago
    )
    [record, event]
  end

  def actor(name)
    OntologyEntity.create!(canonical_key: "actor:#{name.parameterize}", entity_type: "actor", canonical_name: name)
  end

  def tag(event, entity, role: "initiator")
    OntologyEventEntity.create!(ontology_event: event, ontology_entity: entity, role: role)
  end

  test "groups clusters that name the same registry entity" do
    corridor = OntologyEntity.create!(canonical_key: "corridor:hormuz", entity_type: "corridor", canonical_name: "Strait of Hormuz")
    [ "s1", "s2" ].each do |key|
      _c, event = cluster(key: key, title: "Tankers rerouted around the Strait of Hormuz")
      OntologyRelationship.create!(source_node: event, target_node: corridor,
                                  relation_type: "names_entity", confidence: 0.9, derived_by: "news_registry_link_v1")
    end

    SituationBuilder.call(actor_specificity: 1.1)

    situation = OntologyEntity.find_by(entity_type: "situation")
    assert_equal "Strait of Hormuz situation", situation.canonical_name
    assert_equal 2, OntologyEventEntity.where(ontology_entity: situation, role: "in_situation").count
  end

  # The situation carries the entity so ring 3 is reachable from every member,
  # without grouping ever minting a fresh claim that a member named it.
  test "the situation concerns the entity without minting new naming claims" do
    corridor = OntologyEntity.create!(canonical_key: "corridor:hormuz", entity_type: "corridor", canonical_name: "Strait of Hormuz")
    [ "s1", "s2" ].each do |key|
      _c, event = cluster(key: key, title: "Strait of Hormuz reopening talks")
      OntologyRelationship.create!(source_node: event, target_node: corridor,
                                  relation_type: "names_entity", confidence: 0.9, derived_by: "news_registry_link_v1")
    end
    before = OntologyRelationship.where(relation_type: "names_entity").count

    SituationBuilder.call(actor_specificity: 1.1)

    situation = OntologyEntity.find_by(entity_type: "situation", canonical_name: "Strait of Hormuz situation")
    assert OntologyRelationship.exists?(source_node: situation, target_node: corridor, relation_type: "concerns"),
      "the situation is what reaches ring 3"
    assert_equal before, OntologyRelationship.where(relation_type: "names_entity").count,
      "grouping must not mint a naming claim"
  end

  # Frequency cannot tell a country from a story: Japan sits at 6.0% of the
  # window and Houthis at 5.9%. The graph already knows which is a place.
  test "does not build a situation around a country actor" do
    japan = actor("Japan")
    country = OntologyEntity.create!(canonical_key: "country:jpn", entity_type: "country",
                                     canonical_name: "Japan", country_code: "JP")
    OntologyRelationship.create!(source_node: japan, target_node: country,
                                relation_type: "represents_country", confidence: 1.0, derived_by: "ontology_v2_identity_v1")
    [ "j1", "j2" ].each_with_index do |key, i|
      _c, event = cluster(key: key, title: "Unrelated Japanese story number #{i}")
      tag(event, japan)
    end

    SituationBuilder.call(actor_specificity: 1.1)

    assert_empty OntologyEntity.where(entity_type: "situation"),
      "a country is a place, not a story"
  end

  test "builds a situation around a non-country actor" do
    houthis = actor("Houthis")
    [ "h1", "h2" ].each do |key|
      _c, event = cluster(key: key, title: "Houthi forces claim a strike on shipping")
      tag(event, houthis)
    end

    SituationBuilder.call(actor_specificity: 1.1)

    assert_equal "Houthis situation", OntologyEntity.find_by(entity_type: "situation")&.canonical_name
  end

  # Half of all multi-article clusters merge unrelated stories. Grouping those
  # spreads the contamination instead of containing it.
  test "leaves an incoherent cluster out and counts it" do
    houthis = actor("Houthis")
    _c, event = cluster(
      key: "mixed", title: "Jalapenos linked to salmonella outbreak",
      article_titles: [
        "Jalapenos linked to a salmonella outbreak tracked to a Mexican farm",
        "Northcom prepares deployment to support wildfire suppression",
      ]
    )
    tag(event, houthis)
    _c2, event2 = cluster(key: "mixed2", title: "Houthi forces claim a strike on shipping")
    tag(event2, houthis)

    stats = SituationBuilder.call(actor_specificity: 1.1)

    assert_equal 1, stats[:incoherent]
    assert_empty OntologyEventEntity.where(ontology_event: event, role: "in_situation")
  end

  test "a lone cluster is not a situation" do
    houthis = actor("Houthis")
    _c, event = cluster(key: "only", title: "Houthi forces claim a strike")
    tag(event, houthis)

    stats = SituationBuilder.call(actor_specificity: 1.1)

    assert_equal 1, stats[:too_small]
    assert_empty OntologyEntity.where(entity_type: "situation")
  end

  # The threshold itself: an actor that turns up in most of the window is
  # describing the news rather than identifying a story.
  test "ignores an actor that is not specific enough" do
    houthis = actor("Houthis")
    [ "t1", "t2" ].each do |key|
      _c, event = cluster(key: key, title: "Houthi forces claim a strike on shipping")
      tag(event, houthis)
    end

    SituationBuilder.call(actor_specificity: 0.10)

    assert_empty OntologyEntity.where(entity_type: "situation"),
      "present in 100% of the window, so it names no particular story"
  end

  # A hazard names no facility and has no actor of its own, so the rarest-actor
  # rule files it under whoever it happened to mention: the 62-article cluster on
  # the Colombia quake keyed on "United Nations" and joined the UN situation.
  test "an occurrence outranks the actor a hazard report merely mentions" do
    place = OntologyEntity.create!(canonical_key: "place:hazard:earthquake:q1", entity_type: "place",
                                   canonical_name: "5 km S of San Jose del Palmar, Colombia",
                                   metadata: { "latitude" => 4.84, "longitude" => -76.24 })
    un = actor("United Nations")
    [ "q1", "q2" ].each do |key|
      _c, event = cluster(key: key, title: "Quake kills more than 100 in western Colombia")
      tag(event, un)
      OntologyRelationship.create!(source_node: event, target_node: place,
                                   relation_type: HazardOccurrenceLinkService::RELATION_TYPE,
                                   confidence: 0.75, derived_by: "hazard_occurrence_link_v1")
    end

    SituationBuilder.call(actor_specificity: 1.1)

    assert_equal [ "5 km S of San Jose del Palmar, Colombia situation" ],
                 OntologyEntity.where(entity_type: "situation").pluck(:canonical_name)
    assert OntologyRelationship.exists?(relation_type: "concerns", target_node: place),
      "the occurrence is a registry entity like any other, so ring traversal is unchanged"
  end

  # A report that names a strait is about the strait, even when a quake happened
  # in the same country that week.
  test "a named registry entity still outranks an occurrence" do
    corridor = OntologyEntity.create!(canonical_key: "corridor:hormuz", entity_type: "corridor",
                                       canonical_name: "Strait of Hormuz")
    place = OntologyEntity.create!(canonical_key: "place:hazard:earthquake:q1", entity_type: "place",
                                    canonical_name: "near Bandar Abbas, Iran",
                                    metadata: { "latitude" => 27.2, "longitude" => 56.3 })
    [ "h1", "h2" ].each do |key|
      _c, event = cluster(key: key, title: "Tankers rerouted around the Strait of Hormuz")
      OntologyRelationship.create!(source_node: event, target_node: corridor,
                                   relation_type: "names_entity", confidence: 0.9,
                                   derived_by: "news_registry_link_v1")
      OntologyRelationship.create!(source_node: event, target_node: place,
                                   relation_type: HazardOccurrenceLinkService::RELATION_TYPE,
                                   confidence: 0.75, derived_by: "hazard_occurrence_link_v1")
    end

    SituationBuilder.call(actor_specificity: 1.1)

    assert_equal [ "Strait of Hormuz situation" ],
                 OntologyEntity.where(entity_type: "situation").pluck(:canonical_name)
  end
end
