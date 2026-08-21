require "test_helper"

class NewsOntologySyncServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @original_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
    clear_performed_jobs
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
    ActiveJob::Base.queue_adapter = @original_queue_adapter
  end

  test "syncs news sources actors and story clusters into ontology records" do
    article = create_article(
      suffix: "ontology-a",
      publisher: "BBC",
      domain: "bbc.com",
      title: "Israel strikes targets near Isfahan",
      source_kind: "publisher",
      published_at: Time.utc(2026, 3, 25, 12, 0, 0)
    )

    claim = create_claim(article, family: "conflict", event_type: "airstrike", claim_text: article.title)

    cluster = NewsStoryCluster.create!(
      cluster_key: "cluster:ontology-a",
      canonical_title: "Airstrike reported near Isfahan",
      content_scope: "core",
      event_family: "conflict",
      event_type: "airstrike",
      location_name: "Isfahan",
      latitude: 32.65,
      longitude: 51.67,
      geo_precision: "point",
      first_seen_at: article.published_at,
      last_seen_at: article.published_at + 10.minutes,
      article_count: 1,
      source_count: 1,
      cluster_confidence: 0.88,
      verification_status: "single_source",
      lead_news_article: article,
      source_reliability: 0.74,
      geo_confidence: 0.81
    )

    NewsStoryMembership.create!(
      news_story_cluster: cluster,
      news_article: article,
      match_score: 0.93,
      primary: true
    )

    event = NewsEvent.create!(
      news_article: article,
      news_source: article.news_source,
      url: article.url,
      title: article.title,
      name: "Isfahan",
      latitude: 32.65,
      longitude: 51.67,
      # The place anchor is resolved from these, never from `name` -- on a real
      # record that field is as often the publisher as the place.
      geocode_place_name: "Isfahan",
      geocode_country_code: "IR",
      geocode_precision: "city",
      geocode_basis: "title_place",
      geocode_confidence: 0.82,
      tone: -3.0,
      level: "elevated",
      category: "conflict",
      source: article.publisher_domain,
      content_scope: article.content_scope,
      story_cluster_id: cluster.cluster_key,
      published_at: article.published_at,
      fetched_at: article.fetched_at
    )

    synced_event = NewsOntologySyncService.sync_story_cluster(cluster)
    NewsOntologySyncService.sync_source(article.news_source)
    claim.news_actors.each { |actor| NewsOntologySyncService.sync_actor(actor) }

    assert_equal 4, OntologyEntity.count

    source_entity = OntologyEntity.find_by!(canonical_key: "source:#{article.news_source.canonical_key}")
    assert_equal "source", source_entity.entity_type
    assert_equal "BBC", source_entity.canonical_name
    assert OntologyEntityLink.exists?(ontology_entity: source_entity, linkable: article.news_source, role: "publisher")

    place_entity = OntologyEntity.find_by!(canonical_key: "place:isfahan:ir")
    assert_equal "place", place_entity.entity_type
    assert_equal "Isfahan", place_entity.canonical_name

    assert_equal cluster, synced_event.primary_story_cluster
    assert_equal place_entity, synced_event.place_entity
    assert_equal "conflict", synced_event.event_family
    assert_equal "airstrike", synced_event.event_type
    assert_equal "single_source", synced_event.verification_status

    roles = synced_event.ontology_event_entities.includes(:ontology_entity).map { |row| [row.ontology_entity.canonical_name, row.role] }
    assert_includes roles, ["Israel", "initiator"]
    assert_includes roles, ["Iran", "target"]

    assert OntologyEvidenceLink.exists?(ontology_event: synced_event, evidence: cluster, evidence_role: "primary_cluster")
    assert OntologyEvidenceLink.exists?(ontology_event: synced_event, evidence: article, evidence_role: "lead_article")
    assert_equal event.story_cluster_id, cluster.cluster_key
  end

  test "enqueue_for_records schedules source actor and cluster batches" do
    article = create_article(
      suffix: "ontology-enqueue",
      publisher: "BBC",
      domain: "bbc.com",
      title: "Israel strikes targets near Isfahan",
      source_kind: "publisher",
      published_at: Time.utc(2026, 3, 25, 12, 0, 0)
    )
    create_claim(article, family: "conflict", event_type: "airstrike", claim_text: article.title)
    cluster = create_cluster(article, key: "cluster:ontology-enqueue")

    enqueued = NewsOntologySyncService.enqueue_for_records(
      [
        {
          news_source_id: article.news_source_id,
          news_article_id: article.id,
          story_cluster_id: cluster.cluster_key,
        },
      ],
      batch_size: 1
    )

    assert_equal 4, enqueued

    jobs = enqueued_jobs.select { |job| job[:job] == NewsOntologyBatchJob }
    targets = jobs.map { |job| job[:args].first }
    assert_equal 4, jobs.size
    assert_equal 1, targets.count("sources")
    assert_equal 2, targets.count("actors")
    assert_equal 1, targets.count("clusters")
  end

  test "sync_story_cluster removes stale actor memberships and stale lead evidence" do
    article = create_article(
      suffix: "ontology-reconcile-a",
      publisher: "BBC",
      domain: "bbc.com",
      title: "Israel strikes targets near Isfahan",
      source_kind: "publisher",
      published_at: Time.utc(2026, 3, 25, 12, 0, 0)
    )
    claim = create_claim(article, family: "conflict", event_type: "airstrike", claim_text: article.title)
    cluster = create_cluster(article, key: "cluster:ontology-reconcile")

    second_article = create_article(
      suffix: "ontology-reconcile-b",
      publisher: "BBC",
      domain: "bbc.com",
      title: "Follow-up reporting from Isfahan",
      source_kind: "publisher",
      published_at: Time.utc(2026, 3, 25, 12, 5, 0)
    )

    NewsStoryMembership.create!(
      news_story_cluster: cluster,
      news_article: second_article,
      match_score: 0.87,
      primary: true
    )

    synced_event = NewsOntologySyncService.sync_story_cluster(cluster)
    assert_equal 2, synced_event.ontology_event_entities.count
    assert_equal [article.id], synced_event.ontology_evidence_links.where(evidence_role: "lead_article").pluck(:evidence_id)

    claim.news_claim_actors.where(role: "target").delete_all
    cluster.update!(lead_news_article: second_article)

    synced_event = NewsOntologySyncService.sync_story_cluster(cluster)
    roles = synced_event.ontology_event_entities.includes(:ontology_entity).map { |row| [row.ontology_entity.canonical_name, row.role] }

    assert_includes roles, ["Israel", "initiator"]
    refute_includes roles, ["Iran", "target"]
    assert_equal [second_article.id], synced_event.ontology_evidence_links.where(evidence_role: "lead_article").pluck(:evidence_id)
  end

  # The reconciliation above must only sweep roles this sync derives. It used
  # to index every membership on the event, so a cluster re-sync -- which
  # happens the moment a new article joins any active cluster -- deleted the
  # in_situation membership SituationBuilder had written, and every situation
  # lost its members within minutes of being built.
  test "sync_story_cluster leaves the situation membership alone" do
    article = create_article(
      suffix: "ontology-situation-a",
      publisher: "BBC",
      domain: "bbc.com",
      title: "Israel strikes targets near Isfahan",
      source_kind: "publisher",
      published_at: Time.utc(2026, 3, 25, 12, 0, 0)
    )
    create_claim(article, family: "conflict", event_type: "airstrike", claim_text: article.title)
    cluster = create_cluster(article, key: "cluster:ontology-situation")

    event = NewsOntologySyncService.sync_story_cluster(cluster)
    situation = OntologyEntity.create!(
      canonical_key: "situation:actor:1", entity_type: "situation",
      canonical_name: "Isfahan strikes situation",
      metadata: { "derived_by" => "situation_builder_v1" }
    )
    membership = OntologyEventEntity.create!(
      ontology_event: event, ontology_entity: situation,
      role: SituationBuilder::MEMBERSHIP_ROLE, confidence: 0.7
    )

    NewsOntologySyncService.sync_story_cluster(cluster)

    assert OntologyEventEntity.exists?(id: membership.id),
      "a cluster re-sync must not sweep SituationBuilder's membership"
  end

  test "refuses to anchor an event to its publisher" do
    article = create_article(
      suffix: "ontology-pub", publisher: "France 24", domain: "france24.com",
      title: "Clashes reported overnight", source_kind: "publisher",
      published_at: Time.utc(2026, 3, 25, 12, 0, 0)
    )
    create_claim(article, family: "conflict", event_type: "airstrike", claim_text: article.title)
    cluster = create_cluster(article, key: "cluster:ontology-pub")

    # What the geocoder actually produced: the publisher's own country, derived
    # from its domain. The old resolver read `name` and anchored the event to
    # "France 24"; this must produce no place at all rather than a masthead.
    NewsEvent.where(news_article: article).update_all(
      name: "France 24", geocode_place_name: "France 24", geocode_country_code: nil,
      geocode_precision: "country", geocode_basis: "publisher_domain", geocode_confidence: 0.2
    )

    synced_event = NewsOntologySyncService.sync_story_cluster(cluster.reload)

    assert_nil synced_event.place_entity, "a publisher-derived location must not become a place"
    assert_not OntologyEntity.exists?(entity_type: "place", canonical_name: "France 24")
  end

  test "carries a trusted coordinate onto the event itself" do
    article = create_article(
      suffix: "ontology-coord", publisher: "Reuters", domain: "reuters.com",
      title: "Refinery fire in Jazan", source_kind: "publisher",
      published_at: Time.utc(2026, 3, 25, 12, 0, 0)
    )
    create_claim(article, family: "conflict", event_type: "airstrike", claim_text: article.title)
    cluster = create_cluster(article, key: "cluster:ontology-coord")

    NewsEvent.where(news_article: article).update_all(
      latitude: 16.94, longitude: 42.63,
      geocode_place_name: "Jazan", geocode_country_code: "SA",
      geocode_precision: "city", geocode_basis: "ai_place", geocode_confidence: 0.8
    )

    synced_event = NewsOntologySyncService.sync_story_cluster(cluster.reload)

    assert_in_delta 16.94, synced_event.latitude, 0.001
    assert_in_delta 42.63, synced_event.longitude, 0.001
  end

  # The coordinate column is indexed and therefore cheap to query and easy to
  # believe, which makes it exactly the wrong place for a newsroom's location.
  test "refuses to carry a publisher-derived coordinate onto the event" do
    article = create_article(
      suffix: "ontology-pubcoord", publisher: "France 24", domain: "france24.com",
      title: "Clashes reported overnight", source_kind: "publisher",
      published_at: Time.utc(2026, 3, 25, 12, 0, 0)
    )
    create_claim(article, family: "conflict", event_type: "airstrike", claim_text: article.title)
    cluster = create_cluster(article, key: "cluster:ontology-pubcoord")

    # Paris — where the newsroom is, not where the clashes were.
    NewsEvent.where(news_article: article).update_all(
      latitude: 48.85, longitude: 2.35,
      geocode_place_name: "France 24", geocode_country_code: "FR",
      geocode_precision: "country", geocode_basis: "publisher_domain", geocode_confidence: 0.2
    )

    synced_event = NewsOntologySyncService.sync_story_cluster(cluster.reload)

    assert_nil synced_event.latitude, "publisher coordinate must not reach the event"
    assert_nil synced_event.longitude
  end

  test "namesake places in different countries get separate registry rows" do
    a = create_article(
      suffix: "ontology-cali-co", publisher: "Reuters", domain: "reuters.com",
      title: "Explosion in Cali", source_kind: "publisher",
      published_at: Time.utc(2026, 3, 25, 12, 0, 0)
    )
    create_claim(a, family: "conflict", event_type: "airstrike", claim_text: a.title)
    cluster_a = create_cluster(a, key: "cluster:ontology-cali-co")
    NewsEvent.where(news_article: a).update_all(
      latitude: 3.45, longitude: -76.53, geocode_place_name: "Cali", geocode_country_code: "CO",
      geocode_precision: "city", geocode_basis: "ai_place_country", geocode_confidence: 0.9
    )

    b = create_article(
      suffix: "ontology-cali-my", publisher: "Reuters", domain: "reuters.com",
      title: "Flooding near Cali", source_kind: "publisher",
      published_at: Time.utc(2026, 3, 25, 13, 0, 0)
    )
    create_claim(b, family: "hazard", event_type: "flood", claim_text: b.title)
    cluster_b = create_cluster(b, key: "cluster:ontology-cali-my")
    NewsEvent.where(news_article: b).update_all(
      latitude: 3.14, longitude: 101.69, geocode_place_name: "Cali", geocode_country_code: "MY",
      geocode_precision: "city", geocode_basis: "ai_place_country", geocode_confidence: 0.9
    )

    place_a = NewsOntologySyncService.sync_story_cluster(cluster_a.reload).place_entity
    place_b = NewsOntologySyncService.sync_story_cluster(cluster_b.reload).place_entity

    assert_not_equal place_a.id, place_b.id, "one row per (name, country), not per name"
    assert_equal "place:cali:co", place_a.canonical_key
    assert_equal "place:cali:my", place_b.canonical_key
    assert_in_delta(-76.53, place_a.metadata["longitude"], 0.01)
    assert_in_delta 101.69, place_b.metadata["longitude"], 0.01
  end

  test "a less confident resolution cannot drag a place's coordinates" do
    a = create_article(
      suffix: "ontology-guard-hi", publisher: "Reuters", domain: "reuters.com",
      title: "Port strike in Valencia", source_kind: "publisher",
      published_at: Time.utc(2026, 3, 25, 12, 0, 0)
    )
    create_claim(a, family: "unrest", event_type: "strike", claim_text: a.title)
    cluster_hi = create_cluster(a, key: "cluster:ontology-guard-hi")
    NewsEvent.where(news_article: a).update_all(
      latitude: 39.47, longitude: -0.38, geocode_place_name: "Valencia", geocode_country_code: "ES",
      geocode_precision: "city", geocode_basis: "ai_place_country", geocode_confidence: 0.9
    )
    place = NewsOntologySyncService.sync_story_cluster(cluster_hi.reload).place_entity
    assert_in_delta(-0.38, place.metadata["longitude"], 0.01)

    b = create_article(
      suffix: "ontology-guard-lo", publisher: "Reuters", domain: "reuters.com",
      title: "Valencia crowds gather", source_kind: "publisher",
      published_at: Time.utc(2026, 3, 25, 13, 0, 0)
    )
    create_claim(b, family: "unrest", event_type: "protest", claim_text: b.title)
    cluster_lo = create_cluster(b, key: "cluster:ontology-guard-lo")
    # A weaker geocode for the same (name, country) -- Venezuela's Valencia
    # coordinates leaking in under the Spanish key must not move the pin.
    NewsEvent.where(news_article: b).update_all(
      latitude: 10.16, longitude: -68.0, geocode_place_name: "Valencia", geocode_country_code: "ES",
      geocode_precision: "city", geocode_basis: "title_place", geocode_confidence: 0.4
    )
    NewsOntologySyncService.sync_story_cluster(cluster_lo.reload)

    place.reload
    assert_in_delta(-0.38, place.metadata["longitude"], 0.01, "lower confidence must not overwrite")
    assert_in_delta 0.9, place.metadata["geo_confidence"], 0.001

    # An equally or more confident resolution may update it.
    NewsEvent.where(news_article: b).update_all(geocode_confidence: 0.95, latitude: 39.48, longitude: -0.37)
    NewsOntologySyncService.sync_story_cluster(cluster_lo.reload)
    assert_in_delta(-0.37, place.reload.metadata["longitude"], 0.01)
  end

  test "anchors to an existing country entity when only a country is known" do
    country = OntologyEntity.create!(canonical_key: "country:irn", entity_type: "country",
                                     canonical_name: "Iran", country_code: "IR")
    article = create_article(
      suffix: "ontology-country", publisher: "Reuters", domain: "reuters.com",
      title: "Talks resume", source_kind: "publisher",
      published_at: Time.utc(2026, 3, 25, 12, 0, 0)
    )
    create_claim(article, family: "conflict", event_type: "airstrike", claim_text: article.title)
    cluster = create_cluster(article, key: "cluster:ontology-country")

    NewsEvent.where(news_article: article).update_all(
      geocode_place_name: "IR", geocode_country_code: "IR",
      geocode_precision: "country", geocode_basis: "title_country_keyword", geocode_confidence: 0.5
    )

    synced_event = NewsOntologySyncService.sync_story_cluster(cluster.reload)

    assert_equal country, synced_event.place_entity, "should reuse the country node, not mint a place named IR"
    assert_not OntologyEntity.exists?(entity_type: "place", canonical_name: "IR")
  end

  private

  def create_article(suffix:, publisher:, domain:, title:, source_kind:, published_at:)
    source = NewsSource.create!(
      canonical_key: "publisher:#{domain}:#{suffix}",
      name: publisher,
      source_kind: source_kind,
      publisher_domain: domain
    )

    NewsArticle.create!(
      news_source: source,
      url: "https://#{domain}/#{suffix}",
      canonical_url: "https://#{domain}/#{suffix}",
      title: title,
      summary: title,
      normalization_status: "normalized",
      content_scope: "core",
      publisher_name: publisher,
      publisher_domain: domain,
      published_at: published_at,
      fetched_at: published_at + 5.minutes
    )
  end

  def create_cluster(article, key:)
    cluster = NewsStoryCluster.create!(
      cluster_key: key,
      canonical_title: article.title,
      content_scope: "core",
      event_family: "conflict",
      event_type: "airstrike",
      location_name: "Isfahan",
      latitude: 32.65,
      longitude: 51.67,
      geo_precision: "point",
      first_seen_at: article.published_at,
      last_seen_at: article.published_at + 10.minutes,
      article_count: 1,
      source_count: 1,
      cluster_confidence: 0.88,
      verification_status: "single_source",
      lead_news_article: article,
      source_reliability: 0.74,
      geo_confidence: 0.81
    )

    NewsStoryMembership.create!(
      news_story_cluster: cluster,
      news_article: article,
      match_score: 0.93,
      primary: true
    )

    NewsEvent.create!(
      news_article: article,
      news_source: article.news_source,
      url: article.url,
      title: article.title,
      name: "Isfahan",
      latitude: 32.65,
      longitude: 51.67,
      # The place anchor is resolved from these, never from `name` -- on a real
      # record that field is as often the publisher as the place.
      geocode_place_name: "Isfahan",
      geocode_country_code: "IR",
      geocode_precision: "city",
      geocode_basis: "title_place",
      geocode_confidence: 0.82,
      tone: -3.0,
      level: "elevated",
      category: "conflict",
      source: article.publisher_domain,
      content_scope: article.content_scope,
      story_cluster_id: cluster.cluster_key,
      published_at: article.published_at,
      fetched_at: article.fetched_at
    )

    cluster
  end

  def create_claim(article, family:, event_type:, claim_text:)
    claim = NewsClaim.create!(
      news_article: article,
      event_family: family,
      event_type: event_type,
      claim_text: claim_text,
      confidence: 0.92,
      extraction_confidence: 0.91,
      actor_confidence: 0.92,
      event_confidence: 0.93,
      geo_confidence: 0.82,
      source_reliability: 0.74,
      verification_status: "single_source",
      geo_precision: "point",
      extraction_method: "heuristic",
      extraction_version: "headline_rules_v2",
      published_at: article.published_at,
      provenance: { "canonical_url" => article.canonical_url }
    )

    israel = NewsActor.find_or_create_by!(canonical_key: "state:il:test") do |actor|
      actor.name = "Israel"
      actor.actor_type = "state"
      actor.country_code = "IL"
    end
    iran = NewsActor.find_or_create_by!(canonical_key: "state:ir:test") do |actor|
      actor.name = "Iran"
      actor.actor_type = "state"
      actor.country_code = "IR"
    end

    NewsClaimActor.create!(news_claim: claim, news_actor: israel, role: "initiator", position: 0, confidence: 0.93)
    NewsClaimActor.create!(news_claim: claim, news_actor: iran, role: "target", position: 1, confidence: 0.91)
    claim
  end
end
