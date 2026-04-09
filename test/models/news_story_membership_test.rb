require "test_helper"

class NewsStoryMembershipTest < ActiveSupport::TestCase
  setup do
    @cluster = NewsStoryCluster.create!(
      cluster_key: "mem-cluster-001", content_scope: "core", event_family: "conflict",
      event_type: "strike", geo_precision: "unknown",
      first_seen_at: Time.current, last_seen_at: Time.current,
      verification_status: "single_source"
    )
    @source = NewsSource.create!(canonical_key: "mem-src", name: "Src", source_kind: "publisher")
    @article = NewsArticle.create!(
      news_source: @source, url: "https://mem.com/1", canonical_url: "https://mem.com/1",
      normalization_status: "normalized", content_scope: "core"
    )
    @membership = NewsStoryMembership.create!(
      news_story_cluster: @cluster, news_article: @article, match_score: 0.95
    )
  end

  test "valid creation" do
    assert @membership.persisted?
  end

  test "match_score is required" do
    r = NewsStoryMembership.new(news_story_cluster: @cluster, news_article: @article)
    r.match_score = nil
    assert_not r.valid?
    assert_includes r.errors[:match_score], "can't be blank"
  end

  test "belongs_to news_story_cluster" do
    assert_equal @cluster, @membership.news_story_cluster
  end

  test "belongs_to news_article" do
    assert_equal @article, @membership.news_article
  end
end
