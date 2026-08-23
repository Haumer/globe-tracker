require "test_helper"

class SituationHistoryServiceTest < ActiveSupport::TestCase
  def cluster(key:, title: "Strike")
    record = NewsStoryCluster.create!(
      cluster_key: key, canonical_title: title, event_family: "conflict", event_type: "airstrike",
      verification_status: "single_source", geo_precision: "unknown", cluster_confidence: 0.6,
      source_reliability: 0.6, geo_confidence: 0.0, first_seen_at: 3.days.ago, last_seen_at: 1.hour.ago,
      article_count: 1
    )
    event = OntologyEvent.create!(
      canonical_key: "news-story-cluster:#{key}", primary_story_cluster: record,
      event_family: "conflict", event_type: "airstrike", last_seen_at: 1.hour.ago
    )
    [record, event]
  end

  def articles(cluster, count:, published_at:, source: "outlet.example")
    news_source = NewsSource.find_or_create_by!(canonical_key: "publisher:#{source}") do |record|
      record.name = source
      record.source_kind = "publisher"
      record.publisher_domain = source
    end
    count.times do |index|
      article = NewsArticle.create!(
        news_source: news_source,
        url: "https://#{source}/#{cluster.cluster_key}-#{index}",
        canonical_url: "https://#{source}/#{cluster.cluster_key}-#{index}",
        title: "Report #{index}", content_scope: "core", published_at: published_at
      )
      NewsStoryMembership.create!(news_story_cluster: cluster, news_article: article, match_score: 0.9)
    end
  end

  def situation(key:, events:, metadata: {})
    entity = OntologyEntity.create!(
      canonical_key: key, entity_type: "situation", canonical_name: key,
      metadata: { "grouped_by" => "place" }.merge(metadata)
    )
    events.each do |event|
      OntologyEventEntity.create!(ontology_event: event, ontology_entity: entity, role: "in_situation")
    end
    entity
  end

  test "folds window tallies into history and keeps days that left the window" do
    record, event = cluster(key: "h1")
    articles(record, count: 3, published_at: 5.hours.ago)
    old_day = 10.days.ago.utc.to_date.iso8601
    entity = situation(key: "situation:place:h1", events: [event],
                       metadata: { "history" => { old_day => { "a" => 7, "s" => 2 } } })

    SituationHistoryService.call

    history = entity.reload.metadata["history"]
    assert_equal({ "a" => 7, "s" => 2 }, history[old_day], "a day outside the window keeps its stored tally")
    assert_equal 3, history[Time.current.utc.to_date.iso8601]["a"]
  end

  test "records a flare once per refractory period and stores the attention verdict" do
    record, event = cluster(key: "h2")
    %w[one.example two.example three.example].each do |source|
      articles(record, count: 1, published_at: 1.hour.ago, source: source)
    end
    entity = situation(key: "situation:place:h2", events: [event])

    stats = SituationHistoryService.call
    assert_equal 1, stats[:flares_recorded]

    metadata = entity.reload.metadata
    assert_equal "flaring", metadata["attention"]["state"]
    assert_equal 1, metadata["flares"].size

    # Same burst re-assessed inside the refractory gap: still flaring, no new stamp.
    stats = SituationHistoryService.call
    assert_equal 0, stats[:flares_recorded]
    assert_equal 1, entity.reload.metadata["flares"].size
  end

  test "a quiet situation stays quiet and unflared" do
    record, event = cluster(key: "h3")
    articles(record, count: 2, published_at: 2.days.ago)
    entity = situation(key: "situation:place:h3", events: [event])

    SituationHistoryService.call

    metadata = entity.reload.metadata
    assert_equal "quiet", metadata["attention"]["state"]
    assert_equal [], metadata["flares"]
  end
end
