require "test_helper"

class OntologyScorecardServiceTest < ActiveSupport::TestCase
  test "anchor precision counts a publisher-named place as a miss" do
    NewsSource.create!(canonical_key: "publisher:france24.com:sc", name: "France 24",
                       source_kind: "publisher", publisher_domain: "france24.com")

    masthead = ontology_entity("place:france-24", "France 24")
    real = ontology_entity("place:isfahan", "Isfahan")
    ontology_event("event:a", masthead)
    ontology_event("event:b", real)

    anchor = OntologyScorecardService.call.metrics.fetch(:anchor_precision)

    assert_equal 2, anchor.fetch(:total)
    assert_equal 1, anchor.fetch(:count), "the masthead anchor should not be counted as a place"
    assert_in_delta 50.0, anchor.fetch(:value), 0.1
  end

  test "cross domain link rate ignores links that only reach news objects" do
    place = ontology_entity("place:kyiv", "Kyiv")
    actor = ontology_entity("actor:russia", "Russia", type: "actor")
    plant = ontology_entity("plant:zaporizhzhia", "Zaporizhzhia NPP", type: "power_plant")

    newsy = ontology_event("event:newsy", place)
    linked = ontology_event("event:linked", place)

    relationship(newsy, actor, "participated_in_event")
    relationship(linked, plant, "exposed_infrastructure")

    cross = OntologyScorecardService.call.metrics.fetch(:cross_domain_link_rate)

    assert_equal 2, cross.fetch(:total)
    assert_equal 1, cross.fetch(:count), "only the power plant link leaves the news domain"
  end

  test "ingest yield reports each stage of the funnel" do
    article = create_article(suffix: "sc-yield", title: "Missile attack reported near Isfahan")
    NewsClaim.create!(news_article: article, event_family: "conflict", event_type: "missile_attack",
                      claim_text: article.title, primary: true, published_at: article.published_at,
                      confidence: 0.8, provenance: {})

    dropped = create_article(suffix: "sc-drop", title: "Official named in report", scope: "out_of_scope")
    NewsClaim.create!(news_article: dropped, event_family: "general", event_type: "actor_mention",
                      claim_text: dropped.title, primary: true, published_at: dropped.published_at,
                      confidence: 0.5, provenance: {})

    stages = OntologyScorecardService.call.metrics.fetch(:ingest_yield).fetch(:stages)

    assert_equal 2, stages.fetch(:articles)
    assert_equal 1, stages.fetch(:survived_scope), "out_of_scope articles must still count in the denominator"
    assert_equal 2, stages.fetch(:produced_claim)
    assert_equal 1, stages.fetch(:clusterable), "a general/actor_mention claim is not clusterable"
  end

  test "liveness reports the age of each derivation" do
    place = ontology_entity("place:beirut", "Beirut")
    event = ontology_event("event:live", place)
    relationship(event, place, "occurred_at", derived_by: "frozen_v1")
    OntologyRelationship.update_all(updated_at: 40.hours.ago)

    liveness = OntologyScorecardService.call.metrics.fetch(:liveness)

    assert_includes liveness.keys, "frozen_v1"
    assert_in_delta 40.0, liveness.fetch("frozen_v1").fetch(:age_hours), 1.0
  end

  private

  def ontology_entity(key, name, type: "place")
    OntologyEntity.create!(canonical_key: key, entity_type: type, canonical_name: name)
  end

  def ontology_event(key, place)
    OntologyEvent.create!(
      canonical_key: key, event_family: "conflict", event_type: "airstrike",
      status: "active", verification_status: "single_source", geo_precision: "point",
      place_entity: place, first_seen_at: 1.hour.ago, last_seen_at: 1.hour.ago
    )
  end

  def relationship(source, target, relation_type, derived_by: "test_v1")
    OntologyRelationship.create!(
      source_node: source, target_node: target,
      relation_type: relation_type, derived_by: derived_by, confidence: 0.9
    )
  end

  def create_article(suffix:, title:, scope: "core")
    source = NewsSource.create!(canonical_key: "publisher:example.com:#{suffix}", name: "Example Wire",
                                source_kind: "publisher", publisher_domain: "example.com")
    NewsArticle.create!(
      news_source: source, url: "https://example.com/#{suffix}", canonical_url: "https://example.com/#{suffix}",
      title: title, summary: title, normalization_status: "normalized", content_scope: scope,
      publisher_name: "Example Wire", publisher_domain: "example.com",
      published_at: 2.hours.ago, fetched_at: 1.hour.ago
    )
  end
end
