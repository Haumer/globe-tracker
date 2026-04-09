require "test_helper"

class NewsStoryClusterTest < ActiveSupport::TestCase
  setup do
    @cluster = NewsStoryCluster.create!(
      cluster_key: "cluster-001",
      content_scope: "core",
      event_family: "conflict",
      event_type: "military_strike",
      geo_precision: "city",
      first_seen_at: 2.hours.ago,
      last_seen_at: 1.hour.ago,
      verification_status: "multi_source"
    )
  end

  test "valid creation" do
    assert @cluster.persisted?
  end

  test "cluster_key is required" do
    r = NewsStoryCluster.new(content_scope: "core", event_family: "conflict", event_type: "strike", geo_precision: "unknown", first_seen_at: Time.current, last_seen_at: Time.current, verification_status: "single_source")
    r.cluster_key = nil
    assert_not r.valid?
    assert_includes r.errors[:cluster_key], "can't be blank"
  end

  test "event_family is required" do
    r = NewsStoryCluster.new(cluster_key: "x", content_scope: "core", event_type: "strike", geo_precision: "unknown", first_seen_at: Time.current, last_seen_at: Time.current, verification_status: "single_source")
    r.event_family = nil
    assert_not r.valid?
    assert_includes r.errors[:event_family], "can't be blank"
  end

  test "first_seen_at is required" do
    r = NewsStoryCluster.new(cluster_key: "x", content_scope: "core", event_family: "conflict", event_type: "strike", geo_precision: "unknown", last_seen_at: Time.current, verification_status: "single_source")
    assert_not r.valid?
    assert_includes r.errors[:first_seen_at], "can't be blank"
  end

  test "lead_news_article is optional" do
    assert_nil @cluster.lead_news_article
  end

  test "has_many news_story_memberships" do
    assert_respond_to @cluster, :news_story_memberships
  end

  test "has_many news_articles through memberships" do
    assert_respond_to @cluster, :news_articles
  end

  test "has_one ontology_event" do
    assert_respond_to @cluster, :ontology_event
  end

  test "has_many ontology_evidence_links" do
    assert_respond_to @cluster, :ontology_evidence_links
  end
end
