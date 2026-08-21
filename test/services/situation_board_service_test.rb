require "test_helper"

class SituationBoardServiceTest < ActiveSupport::TestCase
  def cluster(key:, title:, lat: nil, lng: nil, seen: 1.day.ago)
    record = NewsStoryCluster.create!(
      cluster_key: key, canonical_title: title, event_family: "conflict", event_type: "airstrike",
      verification_status: "single_source", geo_precision: "unknown", cluster_confidence: 0.6,
      source_reliability: 0.6, geo_confidence: 0.0, first_seen_at: 3.days.ago, last_seen_at: seen,
      article_count: 4
    )
    event = OntologyEvent.create!(
      canonical_key: "news-story-cluster:#{key}", primary_story_cluster: record,
      event_family: "conflict", event_type: "airstrike", last_seen_at: seen,
      latitude: lat, longitude: lng
    )
    [record, event]
  end

  # Attaches real memberships to a cluster. The article_count/source_count
  # columns are deliberately left saying something else, because that is the
  # state 474 of 2,249 live clusters are actually in.
  def articles(cluster, publishers)
    publishers.each_with_index do |publisher, index|
      source = NewsSource.find_or_create_by!(canonical_key: "publisher:#{publisher}") do |record|
        record.name = publisher
        record.source_kind = "publisher"
        record.publisher_domain = publisher
      end
      article = NewsArticle.create!(
        news_source: source,
        url: "https://#{publisher}/#{cluster.cluster_key}-#{index}",
        canonical_url: "https://#{publisher}/#{cluster.cluster_key}-#{index}",
        title: "Report #{index} from #{publisher}",
        content_scope: "core"
      )
      NewsStoryMembership.create!(news_story_cluster: cluster, news_article: article, match_score: 0.9)
    end
    cluster
  end

  def situation(key:, name:, grouped_by:, events:)
    entity = OntologyEntity.create!(
      canonical_key: key, entity_type: "situation", canonical_name: name,
      metadata: { "grouped_by" => grouped_by, "member_count" => events.size }
    )
    events.each do |event|
      OntologyEventEntity.create!(ontology_event: event, ontology_entity: entity, role: "in_situation")
    end
    entity
  end

  test "anchors an entity-keyed situation on the registry entity's own coordinate" do
    corridor = OntologyEntity.create!(
      canonical_key: "corridor:hormuz", entity_type: "corridor", canonical_name: "Strait of Hormuz",
      metadata: { "latitude" => 26.56, "longitude" => 56.27 }
    )
    _c, event = cluster(key: "s1", title: "Tankers reroute", lat: 38.9, lng: -77.0)
    entity = situation(key: "situation:entity:1", name: "Strait of Hormuz situation",
                       grouped_by: "entity", events: [event])
    OntologyRelationship.create!(source_node: entity, target_node: corridor, relation_type: "concerns",
                                confidence: 0.8, derived_by: "situation_builder_v1")

    row = SituationBoardService.call[:situations].first

    assert_equal "registry", row[:anchor][:kind]
    assert_equal 26.56, row[:anchor][:lat]
    assert_equal "Strait of Hormuz", row[:name], "the trailing 'situation' is redundant on a globe"
  end

  # The anchor is the only derived coordinate in the payload, so it has to be a
  # real member position rather than an average that could land in open ocean.
  test "anchors an actor-keyed situation on a member, never on a computed centroid" do
    _a, near_one = cluster(key: "a1", title: "One", lat: 0.0, lng: 0.0)
    _b, near_two = cluster(key: "a2", title: "Two", lat: 1.0, lng: 0.0)
    _c, far = cluster(key: "a3", title: "Three", lat: 60.0, lng: 0.0)
    situation(key: "situation:actor:9", name: "Houthis situation", grouped_by: "actor",
              events: [near_one, near_two, far])

    row = SituationBoardService.call[:situations].first
    anchor = row[:anchor]

    assert_equal "medoid", anchor[:kind]
    assert_includes [[0.0, 0.0], [1.0, 0.0]], [anchor[:lat], anchor[:lng]],
                    "the medoid must be one of the clustered members, not the mean"
    assert(row[:members].any? { |m| m[:lat] == anchor[:lat] && m[:lng] == anchor[:lng] })
  end

  test "an actor-keyed situation reports no rings at all" do
    _c, event = cluster(key: "a1", title: "One", lat: 5.0, lng: 5.0)
    situation(key: "situation:actor:9", name: "NATO situation", grouped_by: "actor", events: [event])

    row = SituationBoardService.call[:situations].first

    assert_nil row[:concerns]
    assert_equal 0, row[:rings][:ring3_countries][:total]
    assert_empty row[:rings][:ring3_countries][:shown]
  end

  # Ranking across rings is meaningless -- a commodity flow scores 0.9 against a
  # country exposure's 0.12 -- so a flattened top-N drops every country.
  test "keeps the three rings apart and ranks inside each" do
    corridor = OntologyEntity.create!(
      canonical_key: "corridor:hormuz", entity_type: "corridor", canonical_name: "Strait of Hormuz",
      metadata: { "latitude" => 26.56, "longitude" => 56.27 }
    )
    country = OntologyEntity.create!(canonical_key: "country:OM", entity_type: "country",
                                     canonical_name: "Oman", country_code: "OM")
    weaker = OntologyEntity.create!(canonical_key: "country:AR", entity_type: "country",
                                    canonical_name: "Argentina", country_code: "AR")
    commodity = OntologyEntity.create!(canonical_key: "commodity:lng", entity_type: "commodity",
                                       canonical_name: "LNG")
    asset = OntologyEntity.create!(canonical_key: "airport:qeshm", entity_type: "airport",
                                   canonical_name: "Qeshm Air Base")

    _c, event = cluster(key: "s1", title: "Tankers reroute", lat: 26.0, lng: 56.0)
    entity = situation(key: "situation:entity:1", name: "Strait of Hormuz situation",
                       grouped_by: "entity", events: [event])
    OntologyRelationship.create!(source_node: entity, target_node: corridor, relation_type: "concerns",
                                confidence: 0.8, derived_by: "situation_builder_v1")

    OntologyRelationship.create!(source_node: corridor, target_node: country, relation_type: "chokepoint_exposure",
                                confidence: 0.6, derived_by: "sync",
                                metadata: { "max_exposure_score" => 0.4, "commodities" => ["lng"] })
    OntologyRelationship.create!(source_node: corridor, target_node: weaker, relation_type: "chokepoint_exposure",
                                confidence: 0.6, derived_by: "sync",
                                metadata: { "max_exposure_score" => 0.005 })
    OntologyRelationship.create!(source_node: corridor, target_node: commodity, relation_type: "flow_dependency",
                                confidence: 0.82, derived_by: "sync", metadata: { "flow_pct" => 30 })
    OntologyRelationship.create!(source_node: corridor, target_node: asset, relation_type: "downstream_exposure",
                                confidence: 0.86, derived_by: "sync", metadata: { "distance_km" => 35.4 })

    rings = SituationBoardService.call[:situations].first[:rings]

    assert_equal ["Oman", "Argentina"], rings[:ring3_countries][:shown].map { |r| r[:name] }
    assert_equal "OM", rings[:ring3_countries][:shown].first[:country_code],
                 "the globe places countries by code, so it has to survive the payload"
    assert_equal ["LNG"], rings[:ring2_commodities][:shown].map { |r| r[:name] }
    assert_in_delta 0.3, rings[:ring2_commodities][:shown].first[:score], 0.001
    assert_equal 35.4, rings[:ring1_assets][:shown].first[:distance_km]
  end

  test "reports the full ring size even when the drawable list is capped" do
    corridor = OntologyEntity.create!(
      canonical_key: "corridor:hormuz", entity_type: "corridor", canonical_name: "Strait of Hormuz",
      metadata: { "latitude" => 26.56, "longitude" => 56.27 }
    )
    _c, event = cluster(key: "s1", title: "Tankers reroute", lat: 26.0, lng: 56.0)
    entity = situation(key: "situation:entity:1", name: "Hormuz situation", grouped_by: "entity",
                       events: [event])
    OntologyRelationship.create!(source_node: entity, target_node: corridor, relation_type: "concerns",
                                confidence: 0.8, derived_by: "situation_builder_v1")

    20.times do |i|
      country = OntologyEntity.create!(canonical_key: "country:#{i}", entity_type: "country",
                                       canonical_name: "Country #{i}", country_code: "C#{i}")
      OntologyRelationship.create!(source_node: corridor, target_node: country,
                                  relation_type: "chokepoint_exposure", confidence: 0.5,
                                  derived_by: "sync", metadata: { "max_exposure_score" => i / 100.0 })
    end

    ring = SituationBoardService.call[:situations].first[:rings][:ring3_countries]

    assert_equal 20, ring[:total], "the panel has to be able to say '+ 8 more' honestly"
    assert_equal SituationBoardService::RING_LIMIT, ring[:shown].size
  end

  test "members carry their place name and geocode provenance" do
    gaza = OntologyEntity.create!(
      canonical_key: "place:gaza-city:ps", entity_type: "place", canonical_name: "Gaza City",
      country_code: "PS", metadata: { "latitude" => 31.5, "longitude" => 34.47 }
    )
    _c, event = cluster(key: "m1", title: "Strikes reported in Gaza City", lat: 31.5, lng: 34.47)
    _c2, other = cluster(key: "m2", title: "Regional powers react", lat: 15.5, lng: 47.5)
    event.update!(place_entity: gaza, geo_precision: "point", geo_confidence: 0.9)
    other.update!(geo_precision: "unknown", geo_confidence: 0.0)
    situation(key: "situation:place:#{gaza.id}", name: "Gaza City", grouped_by: "place", events: [event, other])

    members = SituationBoardService.call[:situations].first[:members]
    placed = members.find { |m| m[:event_id] == event.id }
    vague = members.find { |m| m[:event_id] == other.id }

    assert_equal "Gaza City", placed[:place]
    assert_equal "point", placed[:geo_precision]
    assert_in_delta 0.9, placed[:geo_confidence], 0.001
    assert_nil vague[:place]
    assert_equal "unknown", vague[:geo_precision]
  end

  test "counts members that never got a location instead of dropping them" do
    _a, located = cluster(key: "m1", title: "Located", lat: 10.0, lng: 10.0)
    _b, unlocated = cluster(key: "m2", title: "Not located")
    situation(key: "situation:actor:9", name: "Hamas situation", grouped_by: "actor",
              events: [located, unlocated])

    row = SituationBoardService.call[:situations].first

    assert_equal 2, row[:member_count]
    assert_equal 1, row[:geo_member_count]
    assert_equal 2, row[:members].size
    assert_nil row[:members].find { |m| m[:headline] == "Not located" }[:lat]
  end

  test "skips a situation whose members are all unlocatable rather than guessing one" do
    _a, event = cluster(key: "m1", title: "Nowhere")
    situation(key: "situation:actor:9", name: "Taliban situation", grouped_by: "actor", events: [event])

    assert_empty SituationBoardService.call[:situations]
  end

  test "orders by member count so the rail matches the globe's glyph sizes" do
    _a, small = cluster(key: "s1", title: "Small", lat: 1.0, lng: 1.0)
    _b, big_one = cluster(key: "b1", title: "Big one", lat: 2.0, lng: 2.0)
    _c, big_two = cluster(key: "b2", title: "Big two", lat: 3.0, lng: 3.0)
    situation(key: "situation:actor:1", name: "Small situation", grouped_by: "actor", events: [small])
    situation(key: "situation:actor:2", name: "Big situation", grouped_by: "actor",
              events: [big_one, big_two])

    assert_equal ["Big", "Small"], SituationBoardService.call[:situations].map { |row| row[:name] }
  end

  # Corroboration outranks raw member count: the weak situation below has MORE
  # clusters than the strong one, and still renders second, tiered emerging --
  # four lone mentions from one publisher are not a corroborated story.
  test "tiers thin sourcing as emerging and leads with corroborated situations" do
    weak_events = 4.times.map do |i|
      record, event = cluster(key: "weak#{i}", title: "Lone mention #{i}", lat: 10.0, lng: 10.0)
      articles(record, %w[solo.example])
      event
    end
    situation(key: "situation:actor:1", name: "Weak situation", grouped_by: "actor", events: weak_events)

    strong_events = 3.times.map do |i|
      record, event = cluster(key: "strong#{i}", title: "Big story #{i}", lat: 20.0, lng: 20.0)
      articles(record, [ "a#{i}.example", "b#{i}.example" ])
      event
    end
    situation(key: "situation:actor:2", name: "Strong situation", grouped_by: "actor", events: strong_events)

    rows = SituationBoardService.call[:situations]

    assert_equal [ "Strong", "Weak" ], rows.map { |row| row[:name] }
    assert_equal %w[corroborated emerging], rows.map { |row| row[:tier] }
    assert_equal 6, rows.first[:source_count], "six distinct publishers"
    assert_equal 1, rows.last[:source_count], "the same publisher across four clusters is one source"
  end

  # The columns say 4 and 0; the memberships say 3 articles from 2 sources. A
  # cluster built before its news event exists is stranded at zero and nothing
  # ever recounts it, so the panel has to count rather than read.
  test "counts articles and sources from memberships, not the stale columns" do
    record, event = cluster(key: "c1", title: "Tankers reroute", lat: 1.0, lng: 1.0)
    record.update_columns(article_count: 4, source_count: 0)
    articles(record, %w[reuters reuters upi.com])
    situation(key: "situation:actor:1", name: "Houthis situation", grouped_by: "actor", events: [event])

    member = SituationBoardService.call[:situations].first[:members].first

    assert_equal 3, member[:article_count]
    assert_equal 2, member[:source_count], "two distinct publishers across three reports"
  end

  test "a situation reports its story count and its article count separately" do
    first, one = cluster(key: "c2", title: "One", lat: 1.0, lng: 1.0)
    second, two = cluster(key: "c3", title: "Two", lat: 1.0, lng: 1.0)
    articles(first, %w[reuters upi.com])
    articles(second, %w[reuters])
    situation(key: "situation:actor:2", name: "Houthis situation", grouped_by: "actor", events: [one, two])

    row = SituationBoardService.call[:situations].first

    assert_equal 2, row[:member_count], "two clusters"
    assert_equal 3, row[:article_count], "three reports behind them"
  end

  test "members link to the lead article, falling back to any member article" do
    lead_record, lead_event = cluster(key: "u1", title: "Strike on the depot", lat: 50.4, lng: 30.5)
    articles(lead_record, %w[reuters.com apnews.com])
    lead_article = NewsArticle.find_by!(url: "https://apnews.com/u1-1")
    lead_record.update!(lead_news_article_id: lead_article.id)

    stranded_record, stranded_event = cluster(key: "u2", title: "Follow-up", lat: 50.5, lng: 30.6)
    articles(stranded_record, %w[bbc.com])

    situation(key: "situation:actor:u", name: "Test situation", grouped_by: "actor",
              events: [lead_event, stranded_event])

    members = SituationBoardService.call[:situations].first[:members]

    assert_equal "https://apnews.com/u1-1",
                 members.find { |m| m[:cluster_id] == lead_record.id }[:url]
    assert_equal "https://bbc.com/u2-0",
                 members.find { |m| m[:cluster_id] == stranded_record.id }[:url],
                 "a cluster stranded without a lead article still gets a verifiable link"
  end

  # The suffix is why "Bangkok Post" once resolved to the port of BANGKOK. It
  # reaches one headline in six and was being rendered verbatim.
  test "strips the publisher suffix from the headline it shows" do
    _record, event = cluster(key: "c4", title: "Iran reopens Hormuz to shipping - upi.com", lat: 1.0, lng: 1.0)
    situation(key: "situation:actor:3", name: "Houthis situation", grouped_by: "actor", events: [event])

    member = SituationBoardService.call[:situations].first[:members].first

    assert_equal "Iran reopens Hormuz to shipping", member[:headline]
  end

  # One pass, not repeated: a wire story credited through an aggregator keeps
  # the wire and loses only the domain.
  test "strips one suffix, so a wire credit survives the aggregator's domain" do
    _record, event = cluster(key: "c5", title: "Ports reopen after transit restored - Reuters - tass.com",
                             lat: 1.0, lng: 1.0)
    situation(key: "situation:actor:4", name: "Houthis situation", grouped_by: "actor", events: [event])

    member = SituationBoardService.call[:situations].first[:members].first

    assert_equal "Ports reopen after transit restored - Reuters", member[:headline]
  end

  # Deliberately not guarded by a minimum length, which is the obvious fix and
  # the wrong one. Measured over the 900 suffixed cluster titles on the clone,
  # the shortest remainders are the *correct* strips -- "Greece - U.S.
  # Department of State (.gov)" leaves six characters and is right, "Iran war -
  # AP News" leaves eight -- while the two real false positives ("Money Talks |
  # Un 296 Speciale...", a Swedish subtitle after an en dash) leave 11 and 24.
  # A floor set anywhere useful blocks more good strips than bad ones, so the
  # subtitle case is accepted rather than traded for.
  test "a short remainder is kept, because short does not mean wrong" do
    _record, event = cluster(key: "c6", title: "Iran war - AP News", lat: 1.0, lng: 1.0)
    situation(key: "situation:actor:5", name: "Houthis situation", grouped_by: "actor", events: [event])

    member = SituationBoardService.call[:situations].first[:members].first

    assert_equal "Iran war", member[:headline]
  end

  # The only case the guard exists for: a title that is nothing but a suffix
  # would otherwise render as an empty row.
  test "a title that strips to nothing falls back to the original" do
    _record, event = cluster(key: "c7", title: "- Reuters", lat: 1.0, lng: 1.0)
    situation(key: "situation:actor:6", name: "Houthis situation", grouped_by: "actor", events: [event])

    member = SituationBoardService.call[:situations].first[:members].first

    assert_equal "- Reuters", member[:headline]
  end
end
