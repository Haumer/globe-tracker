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

    place_entity = OntologyEntity.find_by!(canonical_key: "place:isfahan")
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

    israel = NewsActor.create!(
      canonical_key: "state:il:test",
      name: "Israel",
      actor_type: "state",
      country_code: "IL"
    )
    iran = NewsActor.create!(
      canonical_key: "state:ir:test",
      name: "Iran",
      actor_type: "state",
      country_code: "IR"
    )

    NewsClaimActor.create!(news_claim: claim, news_actor: israel, role: "initiator", position: 0, confidence: 0.93)
    NewsClaimActor.create!(news_claim: claim, news_actor: iran, role: "target", position: 1, confidence: 0.91)
    claim
  end
end
