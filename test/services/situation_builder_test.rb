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

  # Scheduled runs need the inverse of persist: a situation whose story left
  # the window would otherwise sit on the board forever at its last
  # member_count, because persist only upserts the groups that exist now.
  test "removes a situation whose story has left the window" do
    stale = OntologyEntity.create!(
      canonical_key: "situation:actor:9999", entity_type: "situation",
      canonical_name: "Last month's story situation",
      metadata: { "derived_by" => "situation_builder_v1", "grouped_by" => "actor" }
    )
    concerns = OntologyRelationship.create!(
      source_node: stale, target_node: actor("Old Faction"),
      relation_type: "concerns", confidence: 0.8, derived_by: "situation_builder_v1"
    )

    corridor = OntologyEntity.create!(canonical_key: "corridor:hormuz", entity_type: "corridor", canonical_name: "Strait of Hormuz")
    [ "s1", "s2" ].each do |key|
      _c, event = cluster(key: key, title: "Tankers rerouted around the Strait of Hormuz")
      OntologyRelationship.create!(source_node: event, target_node: corridor,
                                  relation_type: "names_entity", confidence: 0.9, derived_by: "news_registry_link_v1")
    end

    stats = SituationBuilder.call(actor_specificity: 1.1)

    assert_nil OntologyEntity.find_by(id: stale.id), "the windowed-out situation must be swept"
    assert_nil OntologyRelationship.find_by(id: concerns.id), "its concerns edge goes with it"
    assert OntologyEntity.exists?(entity_type: "situation", canonical_key: "situation:entity:#{corridor.id}"),
      "the live situation survives the sweep"
    assert_equal 1, stats[:removed]
  end

  test "the sweep leaves situation entities other derivers own untouched" do
    foreign = OntologyEntity.create!(
      canonical_key: "situation:manual:1", entity_type: "situation",
      canonical_name: "Operator-curated situation",
      metadata: { "derived_by" => "operator" }
    )

    SituationBuilder.call

    assert OntologyEntity.exists?(id: foreign.id),
      "prune is scoped to DERIVED_BY -- it must not sweep entities it did not build"
  end

  def place(name, key: nil, lat: 35.89, lng: -5.31)
    OntologyEntity.create!(
      canonical_key: key || "place:#{name.parameterize}", entity_type: "place",
      canonical_name: name, metadata: { "latitude" => lat, "longitude" => lng }
    )
  end

  # The largest keyless population: no registry entity, no occurrence, and only
  # country actors. A shared sub-country place is the story of that place.
  test "groups keyless clusters around the place they resolved to" do
    ceuta = place("Ceuta")
    [ "p1", "p2" ].each do |key|
      _c, event = cluster(key: key, title: "Migrant arrivals strain Ceuta services")
      event.update!(place_entity: ceuta)
    end

    SituationBuilder.call(actor_specificity: 1.1)

    situation = OntologyEntity.find_by(entity_type: "situation", canonical_key: "situation:place:#{ceuta.id}")
    assert_not_nil situation, "two keyless clusters sharing a place are that place's story"
    assert_equal "Ceuta situation", situation.canonical_name
    assert OntologyRelationship.exists?(source_node: situation, target_node: ceuta, relation_type: "concerns"),
      "the place carries the coordinate the board anchors on"
  end

  # Place is the weakest key: sharing a city is not sharing a story. The Munich
  # group glued a footballer's injury to a Vietnamese flight probe.
  test "a place group of unrelated stories does not become a situation" do
    munich = place("Munich")
    [
    [ "m1", "Musiala reveals neurological issue", [ "Bayern Munich's Musiala reveals neurological issue after second collapse" ] ],
    [ "m2", "Vietnam ministry seeks flight probe", [ "Vietnam ministry calls for cooperation in probe into flight incident in Munich" ] ]
    ].each do |key, title, articles|
      _c, event = cluster(key: key, title: title, article_titles: articles)
      event.update!(place_entity: munich)
    end

    stats = SituationBuilder.call(actor_specificity: 1.1)

    assert_equal 0, OntologyEntity.where(entity_type: "situation").count,
      "two stories sharing only a city are two singletons, not one situation"
    assert_equal 1, stats[:place_groups_split]
  end

  test "an actor group of unrelated stories splits instead of becoming a junk drawer" do
    un = actor("United Nations")
    [
    [ "u1", "ICC condemns US sanctions", [ "ICC says US sanctions undermine the rule of law", "United Nations court slams flagrant sanctions attack" ] ],
    [ "u2", "North Korea missile launches", [ "North Korea launches missiles as Trump seeks United Nations nuclear talks" ] ],
    [ "u3", "South Sudan election warning", [ "South Sudan election could fuel atrocities warns United Nations commission" ] ]
    ].each do |key, title, articles|
      _c, event = cluster(key: key, title: title, article_titles: articles)
      tag(event, un)
    end

    stats = SituationBuilder.call(actor_specificity: 1.1)

    assert_equal 0, OntologyEntity.where(entity_type: "situation").count,
      "three stories sharing only an actor mention are three singletons, not one situation"
    assert_equal 1, stats[:actor_groups_split]
  end

  test "an actor group with a coherent core keeps it and sheds the stray" do
    un = actor("United Nations")
    [
    [ "c1", "Ceasefire talks resume", [ "United Nations envoy says Gaza ceasefire talks resume in Cairo" ] ],
    [ "c2", "Ceasefire talks stall", [ "Gaza ceasefire talks stall despite United Nations envoy push in Cairo" ] ],
    [ "c3", "Salmonella outbreak widens", [ "Salmonella outbreak tied to jalapenos widens across three states" ] ]
    ].each do |key, title, articles|
      _c, event = cluster(key: key, title: title, article_titles: articles)
      tag(event, un)
    end

    SituationBuilder.call(actor_specificity: 1.1)

    situations = OntologyEntity.where(entity_type: "situation")
    assert_equal 1, situations.count, "the ceasefire pair coheres; the salmonella story is a singleton"
    assert_equal "situation:actor:#{un.id}", situations.first.canonical_key,
      "the largest component keeps the actor's own key"
  end

  test "groups whose referents share a name merge under the strongest kind" do
    corridor = OntologyEntity.create!(canonical_key: "corridor:hormuz", entity_type: "corridor", canonical_name: "Strait of Hormuz")
    hormuz_place = place("Strait Of Hormuz")

    [ "h1", "h2" ].each do |key|
      _c, event = cluster(key: key, title: "Tankers rerouted around the Strait of Hormuz",
                          article_titles: [ "Tankers rerouted around the Strait of Hormuz as talks stall" ])
      OntologyRelationship.create!(source_node: event, target_node: corridor,
                                  relation_type: "names_entity", confidence: 0.9, derived_by: "news_registry_link_v1")
    end
    [ "h3", "h4" ].each do |key|
      _c, event = cluster(key: key, title: "Hormuz shipping grinds to a halt",
                          article_titles: [ "Strait of Hormuz shipping grinds to a halt ahead of ceasefire expiry" ] )
      event.update!(place_entity: hormuz_place)
    end

    stats = SituationBuilder.call(actor_specificity: 1.1)

    situations = OntologyEntity.where(entity_type: "situation")
    assert_equal 1, situations.count, "one strait, one situation"
    assert_equal "situation:entity:#{corridor.id}", situations.first.canonical_key,
      "the entity key wins over the place key"
    assert_equal 4, OntologyEventEntity.where(ontology_entity: situations.first, role: "in_situation").count
    assert_equal 1, stats[:synonym_groups_merged]
  end

  test "a place group splits into components and each coherent one survives" do
    munich = place("Munich")
    [
    [ "q1", "Quake shakes the region", [ "Earthquake damages buildings across Munich suburbs overnight" ] ],
    [ "q2", "Residents flee aftershocks", [ "Aftershocks keep Munich residents outdoors as earthquake damage is assessed" ] ],
    [ "f1", "Musiala injury update", [ "Bayern Munich's Musiala reveals neurological issue after collapse" ] ]
    ].each do |key, title, articles|
      _c, event = cluster(key: key, title: title, article_titles: articles)
      event.update!(place_entity: munich)
    end

    SituationBuilder.call(actor_specificity: 1.1)

    situations = OntologyEntity.where(entity_type: "situation")
    assert_equal 1, situations.count, "the quake pair coheres; the injury story is a singleton"
    assert_equal "situation:place:#{munich.id}", situations.first.canonical_key,
      "the largest component keeps the place's own key"
    assert_equal 2, OntologyEventEntity.where(ontology_entity: situations.first, role: "in_situation").count
  end

  test "a place named with diacritics still subtracts from plain-spelled headlines" do
    # Seen in dev data: the geocoder filed two unrelated Canada stories under
    # "La Cañada", and the ñ kept the place name from being stripped -- the
    # shared word "Canada" then passed the coherence floor on its own.
    canada = place("La Cañada")
    [
    [ "d1", "Care homes testing", [ "Rapid on-site testing at care homes could prevent thousands of visits across Canada" ] ],
    [ "d2", "Foreign visit", [ "Organisation chief plans visit spanning Canada and Britain" ] ]
    ].each do |key, title, articles|
      _c, event = cluster(key: key, title: title, article_titles: articles)
      event.update!(place_entity: canada)
    end

    SituationBuilder.call(actor_specificity: 1.1)

    assert_equal 0, OntologyEntity.where(entity_type: "situation").count,
      "sharing only the place's own name is not coherence"
  end

  test "embeddings outrank word overlap when both clusters carry them" do
    munich = place("Munich")
    # Lexically these two share "collapse" and nothing else; the embeddings say
    # opposite directions, and the measured signal must win over the words.
    pairs = [
      [ "e1", "Stadium roof collapse injures dozens", [ 1.0, 0.0, 0.0 ] ],
      [ "e2", "Talks collapse over stadium financing", [ 0.0, 1.0, 0.0 ] ]
    ]
    pairs.each do |key, title, vector|
      record, event = cluster(key: key, title: title, article_titles: [ title ])
      event.update!(place_entity: munich)
      NewsArticle.where(id: NewsStoryMembership.where(news_story_cluster: record).select(:news_article_id))
        .update_all(title_embedding: "{#{vector.join(',')}}", title_embedding_model: "test")
    end

    SituationBuilder.call(actor_specificity: 1.1)

    assert_equal 0, OntologyEntity.where(entity_type: "situation").count,
      "orthogonal embeddings split the pair regardless of shared words"
  end

  # "Colombia" and "China" arrive as place-typed entities. Keying on them would
  # rebuild the every-story-about-a-country group the actor exclusion prevents.
  test "does not build a situation around a country-named or region-named place" do
    # "Lebanon" is the trap: it is a real country missing from COUNTRY_NAME_MAP,
    # so an exclusion built on that map alone let it through.
    [ place("Colombia", lat: 4.6, lng: -74.1), place("Lebanon", lat: 33.9, lng: 35.5),
      place("Asia", lat: 30.0, lng: 100.0), place("August", lat: 0.0, lng: 0.0) ].each_with_index do |bad, index|
      [ "a#{index}", "b#{index}" ].each do |key|
        _c, event = cluster(key: key, title: "Assorted news item #{key}")
        event.update!(place_entity: bad)
      end
    end

    SituationBuilder.call(actor_specificity: 1.1)

    assert_equal 0, OntologyEntity.where(entity_type: "situation").count,
      "countries, regions and calendar words are places the geocoder minted, not stories"
  end

  test "ignores a place that is not specific enough" do
    everywhere = place("Newsville")
    [ "p1", "p2" ].each do |key|
      _c, event = cluster(key: key, title: "Everything happens in Newsville")
      event.update!(place_entity: everywhere)
    end

    # Both of the window's two clusters carry the place: frequency 1.0 against
    # a threshold of 0.5, so it is describing the window, not a story.
    SituationBuilder.call(actor_specificity: 0.5)

    assert_equal 0, OntologyEntity.where(entity_type: "situation").count
  end

  test "clusters outside the recency window do not form situations" do
    corridor = OntologyEntity.create!(canonical_key: "corridor:hormuz", entity_type: "corridor", canonical_name: "Strait of Hormuz")
    [ "s1", "s2" ].each do |key|
      record, event = cluster(key: key, title: "Tankers rerouted around the Strait of Hormuz")
      record.update!(last_seen_at: (SituationBuilder::WINDOW_DAYS + 2).days.ago)
      OntologyRelationship.create!(source_node: event, target_node: corridor,
                                  relation_type: "names_entity", confidence: 0.9, derived_by: "news_registry_link_v1")
    end

    SituationBuilder.call(actor_specificity: 1.1)

    assert_equal 0, OntologyEntity.where(entity_type: "situation").count,
      "a story last seen #{SituationBuilder::WINDOW_DAYS + 2} days ago is not happening"
  end
end
