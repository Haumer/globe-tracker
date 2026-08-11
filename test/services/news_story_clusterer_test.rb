require "test_helper"

class NewsStoryClustererTest < ActiveSupport::TestCase
  test "clusters the same conflict incident across multiple sources" do
    article_a = create_article(
      suffix: "cluster-a",
      publisher: "BBC",
      domain: "bbc.com",
      title: "Israel strikes targets near Isfahan",
      source_kind: "publisher",
      published_at: Time.utc(2026, 3, 24, 12, 0, 0)
    )
    article_b = create_article(
      suffix: "cluster-b",
      publisher: "Reuters",
      domain: "reuters.com",
      title: "Explosions heard in central Iran after suspected Israeli attack",
      source_kind: "wire",
      published_at: Time.utc(2026, 3, 24, 13, 0, 0)
    )

    create_claim(article_a, family: "conflict", event_type: "airstrike", claim_text: article_a.title)
    create_claim(article_b, family: "conflict", event_type: "missile_attack", claim_text: article_b.title)

    event_a = create_event(article_a, title: article_a.title, location_name: "Isfahan", lat: 32.65, lng: 51.67)
    event_b = create_event(article_b, title: article_b.title, location_name: "Isfahan", lat: 32.64, lng: 51.70)

    records = [
      {
        news_article_id: article_a.id,
        title: event_a.title,
        name: event_a.name,
        latitude: event_a.latitude,
        longitude: event_a.longitude,
        published_at: event_a.published_at,
        content_scope: "core",
        news_source_id: article_a.news_source_id,
      },
      {
        news_article_id: article_b.id,
        title: event_b.title,
        name: event_b.name,
        latitude: event_b.latitude,
        longitude: event_b.longitude,
        published_at: event_b.published_at,
        content_scope: "core",
        news_source_id: article_b.news_source_id,
      },
    ]

    NewsStoryClusterer.assign_records(records)

    cluster_key = event_a.reload.story_cluster_id
    assert_not_nil cluster_key
    assert cluster_key.present?
    assert_equal cluster_key, event_b.reload.story_cluster_id

    cluster = NewsStoryCluster.find_by!(cluster_key: cluster_key)
    assert_equal 2, cluster.article_count
    assert_equal 2, cluster.source_count
    assert_equal "multi_source", cluster.verification_status
    assert_operator cluster.source_reliability, :>, 0.7
    assert_operator cluster.geo_confidence, :>, 0.7
    assert_equal "point", cluster.geo_precision
    assert_includes %w[airstrike missile_attack], cluster.event_type
  end

  test "separates diplomacy from conflict even with the same actors" do
    conflict_article = create_article(
      suffix: "cluster-c",
      publisher: "BBC",
      domain: "bbc.com",
      title: "Israel strikes targets near Isfahan",
      source_kind: "publisher",
      published_at: Time.utc(2026, 3, 24, 12, 0, 0)
    )
    diplomacy_article = create_article(
      suffix: "cluster-d",
      publisher: "Reuters",
      domain: "reuters.com",
      title: "Iran and Israel exchange messages through mediators",
      source_kind: "wire",
      published_at: Time.utc(2026, 3, 24, 14, 0, 0)
    )

    create_claim(conflict_article, family: "conflict", event_type: "airstrike", claim_text: conflict_article.title)
    create_claim(diplomacy_article, family: "diplomacy", event_type: "negotiation", claim_text: diplomacy_article.title)

    conflict_event = create_event(conflict_article, title: conflict_article.title, location_name: "Isfahan", lat: 32.65, lng: 51.67)
    diplomacy_event = create_event(diplomacy_article, title: diplomacy_article.title, location_name: "Muscat", lat: 23.59, lng: 58.41)

    records = [
      {
        news_article_id: conflict_article.id,
        title: conflict_event.title,
        name: conflict_event.name,
        latitude: conflict_event.latitude,
        longitude: conflict_event.longitude,
        published_at: conflict_event.published_at,
        content_scope: "core",
        news_source_id: conflict_article.news_source_id,
      },
      {
        news_article_id: diplomacy_article.id,
        title: diplomacy_event.title,
        name: diplomacy_event.name,
        latitude: diplomacy_event.latitude,
        longitude: diplomacy_event.longitude,
        published_at: diplomacy_event.published_at,
        content_scope: "core",
        news_source_id: diplomacy_article.news_source_id,
      },
    ]

    NewsStoryClusterer.assign_records(records)

    refute_equal conflict_event.reload.story_cluster_id, diplomacy_event.reload.story_cluster_id
    assert_equal 2, NewsStoryCluster.count
  end

  test "reclustering the same article is idempotent" do
    article = create_article(
      suffix: "cluster-recluster",
      publisher: "Reuters",
      domain: "reuters.com",
      title: "Explosions heard in central Iran after suspected Israeli attack",
      source_kind: "wire",
      published_at: Time.utc(2026, 3, 24, 13, 0, 0)
    )

    create_claim(article, family: "conflict", event_type: "missile_attack", claim_text: article.title)
    create_event(article, title: article.title, location_name: "Isfahan", lat: 32.64, lng: 51.70)

    first_cluster_key = NewsStoryClusterer.recluster_article(article)
    second_cluster_key = NewsStoryClusterer.recluster_article(article)

    assert_equal first_cluster_key, second_cluster_key
    assert_equal 1, NewsStoryCluster.count
    assert_equal 1, NewsStoryMembership.count
    assert_equal first_cluster_key, article.news_events.first.reload.story_cluster_id
  end

  test "syndication_groups collapses outlets running identical wire copy" do
    payloads = [
      { title: "Blast reported at Kyiv power substation", source_id: 1 },
      { title: "Blast reported at Kyiv power substation", source_id: 2 },
      { title: "Blast reported at Kyiv power substation", source_id: 3 },
    ]
    groups = NewsStoryClusterer.send(:syndication_groups, payloads)

    assert_equal 1, groups.size
    assert_equal [ 1, 2, 3 ], groups.first[:source_ids]
  end

  test "syndication_groups keeps independently written headlines apart" do
    payloads = [
      { title: "Blast reported at Kyiv power substation", source_id: 1 },
      { title: "Ukraine says grid damaged in overnight drone wave", source_id: 2 },
    ]
    assert_equal 2, NewsStoryClusterer.send(:syndication_groups, payloads).size
  end

  test "a headline extension is not treated as syndication" do
    # Containment would score 1.0 here. Competing newsrooms routinely publish
    # one headline inside another, so only Jaccard may drive this decision.
    payloads = [
      { title: "Strike hits fuel depot", source_id: 1 },
      { title: "Strike hits fuel depot, at least fifty reported dead", source_id: 2 },
    ]
    assert_equal 2, NewsStoryClusterer.send(:syndication_groups, payloads).size
  end

  test "saturating_factor keeps discriminating past the old hard caps" do
    f = ->(n) { NewsStoryClusterer.send(:saturating_factor, n, NewsStoryClusterer::SOURCE_FACTOR_SATURATION) }

    assert_equal 0.0, f.call(0)
    assert_operator f.call(2), :>, f.call(1)
    # The old implementation pinned everything at and above 3 to 1.0.
    assert_operator f.call(8), :>, f.call(3)
    assert_operator f.call(1.0), :<=, 1.0
    assert_in_delta 1.0, f.call(NewsStoryClusterer::SOURCE_FACTOR_SATURATION), 0.001
    assert_equal 1.0, f.call(500)
  end

  test "three outlets carrying one wire story do not count as corroboration" do
    wire_headline = "Explosions heard in central Iran after suspected Israeli attack"
    articles = %w[reuters.com abc.net.au straitstimes.com].each_with_index.map do |domain, idx|
      create_article(
        suffix: "syndicated-#{idx}",
        publisher: domain,
        domain: domain,
        title: wire_headline,
        source_kind: idx.zero? ? "wire" : "publisher",
        published_at: Time.utc(2026, 3, 24, 13 + idx, 0, 0)
      )
    end

    records = articles.map do |article|
      create_claim(article, family: "conflict", event_type: "missile_attack", claim_text: article.title)
      event = create_event(article, title: article.title, location_name: "Isfahan", lat: 32.64, lng: 51.70)
      {
        news_article_id: article.id,
        title: event.title,
        name: event.name,
        latitude: event.latitude,
        longitude: event.longitude,
        published_at: event.published_at,
        content_scope: "core",
        news_source_id: article.news_source_id,
      }
    end

    NewsStoryClusterer.assign_records(records)
    cluster = NewsStoryCluster.find_by!(cluster_key: articles.first.news_events.first.reload.story_cluster_id)

    assert_equal 3, cluster.article_count
    assert_equal 3, cluster.source_count, "raw outlet count should still be recorded"
    assert_equal 1, cluster.metadata["independent_source_ids"].size
    assert_equal 2, cluster.metadata["syndicated_article_count"]
    assert_equal "single_source", cluster.verification_status,
                 "one newsroom republished three times is not corroboration"
  end

  # The defect this floor exists for. Both articles are conflict/airstrike, in
  # the same window, at the same place, and share both actors -- every signal
  # the scorer weighs except the words agrees. Before the floor that reached
  # 0.705 against a threshold of 0.67 and merged two stories with nothing in
  # common, which is how a food-safety recall joined a cluster of shipping
  # attacks.
  test "does not merge two unrelated reports that share only their actors" do
    strike = create_article(
      suffix: "topic-a", publisher: "BBC", domain: "bbc.com",
      title: "Israel strikes targets near Isfahan",
      source_kind: "publisher", published_at: Time.utc(2026, 3, 24, 12, 0, 0)
    )
    unrelated = create_article(
      suffix: "topic-b", publisher: "Reuters", domain: "reuters.com",
      title: "Jalapeno recall widens as salmonella cases mount",
      source_kind: "wire", published_at: Time.utc(2026, 3, 24, 13, 0, 0)
    )

    records = [strike, unrelated].map do |article|
      create_claim(article, family: "conflict", event_type: "airstrike", claim_text: article.title)
      event = create_event(article, title: article.title, location_name: "Isfahan", lat: 32.65, lng: 51.67)
      {
        news_article_id: article.id, title: event.title, name: event.name,
        latitude: event.latitude, longitude: event.longitude,
        published_at: event.published_at, content_scope: "core",
        news_source_id: article.news_source_id,
      }
    end

    NewsStoryClusterer.assign_records(records)

    assert_not_equal strike.news_events.first.reload.story_cluster_id,
                     unrelated.news_events.first.reload.story_cluster_id,
                     "sharing actors and a place is a shared topic, not a shared story"
  end

  # The floor must not cost the case the clusterer exists for: independent
  # newsrooms writing different headlines about one incident.
  test "still merges independently written headlines about one incident" do
    articles = [
      ["merge-a", "BBC", "bbc.com", "Israel strikes military targets near Isfahan", "publisher", 12],
      ["merge-b", "Reuters", "reuters.com", "Explosions near Isfahan as Israel strikes Iranian targets", "wire", 13],
    ].map do |suffix, publisher, domain, title, kind, hour|
      create_article(suffix: suffix, publisher: publisher, domain: domain, title: title,
                     source_kind: kind, published_at: Time.utc(2026, 3, 24, hour, 0, 0))
    end

    records = articles.map do |article|
      create_claim(article, family: "conflict", event_type: "airstrike", claim_text: article.title)
      event = create_event(article, title: article.title, location_name: "Isfahan", lat: 32.65, lng: 51.67)
      {
        news_article_id: article.id, title: event.title, name: event.name,
        latitude: event.latitude, longitude: event.longitude,
        published_at: event.published_at, content_scope: "core",
        news_source_id: article.news_source_id,
      }
    end

    NewsStoryClusterer.assign_records(records)

    assert_equal articles.first.news_events.first.reload.story_cluster_id,
                 articles.last.news_events.first.reload.story_cluster_id
  end

  # A cluster asserts that every member is the same story as every other, so the
  # floor is checked against all of them, not just the lead. The third headline
  # here is a close match for the second but shares nothing with the first, and
  # gating on the lead alone would admit it and assert a pair nobody checked.
  test "an article must match every member, not just the lead headline" do
    titles = [
      "Israel strikes military targets near Isfahan",
      "Israeli jets hit Isfahan military sites overnight",
      "Ukraine drone attack hits Russian refinery in Tyumen",
    ]
    articles = titles.each_with_index.map do |title, i|
      create_article(suffix: "link-#{i}", publisher: "Pub#{i}", domain: "pub#{i}.com",
                     title: title, source_kind: "publisher",
                     published_at: Time.utc(2026, 3, 24, 12 + i, 0, 0))
    end

    records = articles.map do |article|
      create_claim(article, family: "conflict", event_type: "airstrike", claim_text: article.title)
      event = create_event(article, title: article.title, location_name: "Isfahan", lat: 32.65, lng: 51.67)
      {
        news_article_id: article.id, title: event.title, name: event.name,
        latitude: event.latitude, longitude: event.longitude,
        published_at: event.published_at, content_scope: "core",
        news_source_id: article.news_source_id,
      }
    end

    NewsStoryClusterer.assign_records(records)
    keys = articles.map { |article| article.news_events.first.reload.story_cluster_id }

    assert_equal keys[0], keys[1], "two reports of the Isfahan strike are one story"
    assert_not_equal keys[1], keys[2],
      "the drone story matches no member of that cluster and must not join it"
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
      content_scope: "core",
      publisher_name: publisher,
      publisher_domain: domain,
      published_at: published_at,
      fetched_at: published_at + 5.minutes
    )
  end

  def create_event(article, title:, location_name:, lat:, lng:)
    NewsEvent.create!(
      news_article: article,
      news_source: article.news_source,
      url: article.url,
      title: title,
      name: location_name,
      latitude: lat,
      longitude: lng,
      tone: -3.0,
      level: "elevated",
      category: "conflict",
      source: article.publisher_domain,
      content_scope: article.content_scope,
      published_at: article.published_at,
      fetched_at: article.fetched_at
    )
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
      source_reliability: article.news_source.source_kind == "wire" ? 0.92 : 0.74,
      verification_status: "single_source",
      geo_precision: "point",
      extraction_method: "heuristic",
      extraction_version: "headline_rules_v2",
      published_at: article.published_at,
      provenance: { "canonical_url" => article.canonical_url }
    )

    israel = NewsActor.find_or_create_by!(canonical_key: "state:il") do |actor|
      actor.name = "Israel"
      actor.actor_type = "state"
      actor.country_code = "IL"
    end
    iran = NewsActor.find_or_create_by!(canonical_key: "state:ir") do |actor|
      actor.name = "Iran"
      actor.actor_type = "state"
      actor.country_code = "IR"
    end

    NewsClaimActor.create!(news_claim: claim, news_actor: israel, role: "initiator", position: 0, confidence: 0.93)
    NewsClaimActor.create!(news_claim: claim, news_actor: iran, role: family == "diplomacy" ? "participant" : "target", position: 1, confidence: 0.91)
  end
end

class NewsStoryClustererRebuildTest < ActiveSupport::TestCase
  # A strict-location claim whose article has no NewsEvent row cannot rebuild
  # its payload. That is exactly the state every ingest service used to cluster
  # in, because assign_clusters ran before NewsEvent.upsert_all. The cluster
  # must still come out with an honest article_count and a last_seen_at that
  # keeps it inside the candidate window -- otherwise it can never be joined.
  test "cluster rebuild survives a member whose payload cannot be reconstructed" do
    article = build_article("no-event")
    build_claim(article, event_type: "ground_operation")

    assert_nil NewsStoryClusterer.send(:build_payload, article, article.news_claims.first, {}),
      "expected a strict-location claim with no NewsEvent to be unreconstructable"

    NewsStoryClusterer.assign_records([
      {
        news_article_id: article.id,
        title: article.title,
        name: "Kharkiv",
        latitude: 49.99,
        longitude: 36.23,
        published_at: article.published_at,
        content_scope: "core",
        news_source_id: article.news_source_id,
      },
    ])

    cluster = NewsStoryCluster.joins(:news_story_memberships)
      .where(news_story_memberships: { news_article_id: article.id }).first
    assert_not_nil cluster, "expected the article to be clustered"
    assert_equal 1, cluster.article_count, "cluster must report the members it actually has"
    assert_operator cluster.last_seen_at, :>=, cluster.first_seen_at
  end

  test "information family is clusterable" do
    assert_includes NewsStoryClusterer::CLUSTERABLE_EVENT_FAMILIES, "information"

    article = build_article("accusation")
    build_claim(article, event_type: "accusation_statement", family: "information")
    NewsEvent.create!(
      news_article: article, news_source: article.news_source, url: article.url,
      title: article.title, name: "Kyiv", latitude: 50.45, longitude: 30.52,
      tone: -2.0, level: "elevated", category: "conflict", source: "test",
      content_scope: "core", published_at: article.published_at, fetched_at: article.fetched_at
    )

    NewsStoryClusterer.assign_records([
      { news_article_id: article.id, title: article.title, name: "Kyiv",
        latitude: 50.45, longitude: 30.52, published_at: article.published_at,
        content_scope: "core", news_source_id: article.news_source_id },
    ])

    assert NewsStoryMembership.exists?(news_article_id: article.id),
      "an information/accusation_statement claim must reach a cluster"
  end

  private

  def build_article(suffix)
    source = NewsSource.create!(
      canonical_key: "publisher:example.com:#{suffix}",
      name: "Example", source_kind: "publisher", publisher_domain: "example.com"
    )
    NewsArticle.create!(
      news_source: source,
      url: "https://example.com/#{suffix}",
      canonical_url: "https://example.com/#{suffix}",
      title: "Russia shells Ukraine positions near the front",
      summary: "Russia shells Ukraine positions near the front",
      content_scope: "core",
      publisher_name: "Example", publisher_domain: "example.com",
      published_at: Time.utc(2026, 3, 24, 12, 0, 0),
      fetched_at: Time.utc(2026, 3, 24, 12, 5, 0)
    )
  end

  def build_claim(article, event_type:, family: "conflict")
    claim = NewsClaim.create!(
      news_article: article, event_family: family, event_type: event_type,
      claim_text: article.title, confidence: 0.9, extraction_confidence: 0.9,
      actor_confidence: 0.9, event_confidence: 0.9, geo_confidence: 0.8,
      source_reliability: 0.75, verification_status: "single_source",
      geo_precision: "point", extraction_method: "heuristic",
      extraction_version: "headline_rules_v2", published_at: article.published_at
    )
    russia = NewsActor.find_or_create_by!(canonical_key: "state:ru") do |actor|
      actor.name = "Russia"; actor.actor_type = "state"; actor.country_code = "RU"
    end
    NewsClaimActor.create!(news_claim: claim, news_actor: russia, role: "initiator", position: 0, confidence: 0.9)
    claim
  end
end

# The semantic gate. Two floors now have to hold before a merge: shared words,
# and shared meaning. These tests drive the second one with hand-built unit
# vectors rather than real embeddings, so they assert the linkage and the tier
# logic -- which is what the traps in this file are about -- and not the
# quality of any particular model's output.
module CosineGateFixtures
  # Deliberately near-identical headlines: they clear MINIMUM_TEXT_SIMILARITY
  # comfortably, so anything that separates them here is the cosine and nothing
  # else.
  TITLES = [
    "Russia shells Ukraine positions near the front line",
    "Russia shells Ukraine positions near the front village",
    "Russia shells Ukraine positions near the front border",
  ].freeze

  # Unit vectors at a chosen angle, so the cosine between any two is exactly
  # cos(theta_a - theta_b) and every threshold in the gate can be aimed at.
  def unit(radians)
    [ Math.cos(radians), Math.sin(radians) ]
  end

  def article_with(suffix, title:, embedding:, published_at: Time.utc(2026, 3, 24, 12, 0, 0))
    source = NewsSource.create!(
      canonical_key: "publisher:example.com:#{suffix}", name: "Example",
      source_kind: "publisher", publisher_domain: "example.com"
    )
    article = NewsArticle.create!(
      news_source: source, url: "https://example.com/#{suffix}",
      canonical_url: "https://example.com/#{suffix}", title: title, summary: title,
      content_scope: "core", publisher_name: "Example", publisher_domain: "example.com",
      published_at: published_at, fetched_at: published_at,
      title_embedding: embedding, title_embedding_model: "test@2",
      title_embedding_digest: (NewsHeadlineEmbeddingService.digest_for(title) if embedding)
    )
    claim = NewsClaim.create!(
      news_article: article, event_family: "conflict", event_type: "airstrike",
      claim_text: title, confidence: 0.9, extraction_confidence: 0.9,
      actor_confidence: 0.9, event_confidence: 0.9, geo_confidence: 0.8,
      source_reliability: 0.75, verification_status: "single_source",
      geo_precision: "point", extraction_method: "heuristic",
      extraction_version: "headline_rules_v2", published_at: published_at
    )
    russia = NewsActor.find_or_create_by!(canonical_key: "state:ru") do |actor|
      actor.name = "Russia"; actor.actor_type = "state"; actor.country_code = "RU"
    end
    NewsClaimActor.create!(news_claim: claim, news_actor: russia, role: "initiator", position: 0, confidence: 0.9)
    article
  end

  def record_for(article)
    {
      news_article_id: article.id, title: article.title, published_at: article.published_at,
      content_scope: "core", news_source_id: article.news_source_id,
    }
  end

  def cluster_count_for(articles)
    NewsStoryMembership.where(news_article_id: articles.map(&:id)).distinct.count(:news_story_cluster_id)
  end

  def assign(*articles)
    NewsStoryClusterer.assign_records(articles.map { |article| record_for(article) })
  end
end

class NewsStoryClustererCosineGateTest < ActiveSupport::TestCase
  include CosineGateFixtures

  test "headlines that share words but not meaning are not one story" do
    a = article_with("cos-a", title: TITLES[0], embedding: unit(0.0))
    b = article_with("cos-b", title: TITLES[1], embedding: unit(1.2), published_at: Time.utc(2026, 3, 24, 13, 0, 0))

    assert_operator NewsHeadlineEmbeddingService.cosine(unit(0.0), unit(1.2)), :<,
      NewsStoryClusterer::MINIMUM_HEADLINE_COSINE

    assign(a, b)

    assert_equal 2, cluster_count_for([ a, b ]), "a cosine below the floor must veto the merge"
  end

  test "the same headlines merge when the embedding agrees" do
    a = article_with("cos-c", title: TITLES[0], embedding: unit(0.0))
    b = article_with("cos-d", title: TITLES[1], embedding: unit(0.1), published_at: Time.utc(2026, 3, 24, 13, 0, 0))

    assert_operator NewsHeadlineEmbeddingService.cosine(unit(0.0), unit(0.1)), :>=,
      NewsStoryClusterer::HEADLINE_COSINE_CERTAIN

    assign(a, b)

    assert_equal 1, cluster_count_for([ a, b ]), "the control must still merge, or the test proves nothing"
  end

  # The trap this whole line of work keeps hitting: a cluster asserts every
  # member is the same story as every other, so a gate that checks only the
  # lead leaves the member-to-member pairs unchecked. Those ran at 5.0%
  # precision against 48.8% for gated pairs.
  test "one member below the floor vetoes the cluster even when the lead is close" do
    a = article_with("cos-e", title: TITLES[0], embedding: unit(0.0))
    b = article_with("cos-f", title: TITLES[1], embedding: unit(0.5), published_at: Time.utc(2026, 3, 24, 13, 0, 0))
    assign(a, b)
    assert_equal 1, cluster_count_for([ a, b ])

    # Placed so it is certain against the lead (a) and below the floor against
    # the other member (b): the two answers disagree, which is the only
    # arrangement that can tell complete linkage from lead-only gating.
    c = article_with("cos-g", title: TITLES[2], embedding: unit(-0.55), published_at: Time.utc(2026, 3, 24, 14, 0, 0))
    assert_operator NewsHeadlineEmbeddingService.cosine(unit(-0.55), unit(0.0)), :>=,
      NewsStoryClusterer::HEADLINE_COSINE_CERTAIN, "must be certain against the lead"
    assert_operator NewsHeadlineEmbeddingService.cosine(unit(-0.55), unit(0.5)), :<,
      NewsStoryClusterer::MINIMUM_HEADLINE_COSINE, "and fail the floor against the second member"

    assign(c)

    assert_equal 2, cluster_count_for([ a, b, c ]),
      "complete linkage: the worst member decides, not the lead"
  end

  # Failing open. A corpus mid-backfill, or an embedding API that is down, must
  # leave the clusterer on its lexical floor rather than send every article to
  # its own singleton -- nothing revisits a singleton.
  test "articles without an embedding cluster exactly as they did before" do
    a = article_with("cos-h", title: TITLES[0], embedding: nil)
    b = article_with("cos-i", title: TITLES[1], embedding: nil, published_at: Time.utc(2026, 3, 24, 13, 0, 0))

    assign(a, b)

    assert_equal 1, cluster_count_for([ a, b ])
  end

  # A headline revised by a later poll leaves the row's vector describing text
  # that is no longer the text being clustered. Comparing this article's words
  # against another headline's vector is a wrong answer rather than a missing
  # one, so the stale vector is dropped and the pair falls back to lexical.
  test "a vector that does not describe the title being clustered is not used" do
    a = article_with("stale-a", title: TITLES[0], embedding: unit(0.0))
    b = article_with("stale-b", title: TITLES[1], embedding: unit(1.2), published_at: Time.utc(2026, 3, 24, 13, 0, 0))
    b.update_columns(title_embedding_digest: NewsHeadlineEmbeddingService.digest_for("a headline it no longer has"))

    assign(a, b)

    assert_equal 1, cluster_count_for([ a, b ]),
      "a stale vector must be ignored, leaving the lexical floor to decide"
  end

  test "an unembedded article is never sent to the adjudicator" do
    a = article_with("cos-j", title: TITLES[0], embedding: nil)
    b = article_with("cos-k", title: TITLES[1], embedding: nil, published_at: Time.utc(2026, 3, 24, 13, 0, 0))

    NewsClusterAdjudicator.stub(:call, ->(*) { flunk "no embedding means nothing to be undecided about" }) do
      assign(a, b)
    end

    assert_equal 1, cluster_count_for([ a, b ])
  end
end

class NewsStoryClustererAdjudicationTest < ActiveSupport::TestCase
  include CosineGateFixtures

  # Between the two bounds the embedding is genuinely undecided, and that is the
  # only place a model call is worth making.
  def band_pair
    a = article_with("band-a", title: TITLES[0], embedding: unit(0.0))
    b = article_with("band-b", title: TITLES[1], embedding: unit(0.9), published_at: Time.utc(2026, 3, 24, 13, 0, 0))
    cosine = NewsHeadlineEmbeddingService.cosine(unit(0.0), unit(0.9))
    assert_operator cosine, :>=, NewsStoryClusterer::MINIMUM_HEADLINE_COSINE
    assert_operator cosine, :<, NewsStoryClusterer::HEADLINE_COSINE_CERTAIN
    [ a, b ]
  end

  test "the band asks the model, and merges when it picks a cluster" do
    a, b = band_pair
    assign(a)

    verdict = NewsClusterAdjudicator::Verdict.new(index: 0, basis: "same shelling", called: true)
    NewsClusterAdjudicator.stub(:call, verdict) { assign(b) }

    assert_equal 1, cluster_count_for([ a, b ])
  end

  test "the band splits when the model says none" do
    a, b = band_pair
    assign(a)

    NewsClusterAdjudicator.stub(:call, NewsClusterAdjudicator::NONE) { assign(b) }

    assert_equal 2, cluster_count_for([ a, b ]), "none is a decision, not a fallback"
  end

  # An outage must not silently fragment the corpus, so an unreachable model
  # leaves the decision where it was before the model existed: merged.
  test "an unreachable model falls back to the pre-model behaviour" do
    a, b = band_pair
    assign(a)

    NewsClusterAdjudicator.stub(:call, NewsClusterAdjudicator::UNAVAILABLE) { assign(b) }

    assert_equal 1, cluster_count_for([ a, b ])
  end

  test "a certain merge costs nothing" do
    a = article_with("certain-a", title: TITLES[0], embedding: unit(0.0))
    b = article_with("certain-b", title: TITLES[1], embedding: unit(0.1), published_at: Time.utc(2026, 3, 24, 13, 0, 0))
    assign(a)

    NewsClusterAdjudicator.stub(:call, ->(*) { flunk "above the certain bound the embedding decides alone" }) do
      assign(b)
    end

    assert_equal 1, cluster_count_for([ a, b ])
  end
end
