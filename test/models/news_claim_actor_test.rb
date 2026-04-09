require "test_helper"

class NewsClaimActorTest < ActiveSupport::TestCase
  setup do
    @source = NewsSource.create!(canonical_key: "bbc-claim-actor", name: "BBC", source_kind: "publisher")
    @article = NewsArticle.create!(
      news_source: @source, url: "https://bbc.com/ca1", canonical_url: "https://bbc.com/ca1",
      normalization_status: "normalized", content_scope: "core"
    )
    @claim = NewsClaim.create!(
      news_article: @article, event_type: "diplomacy", event_family: "political",
      extraction_method: "heuristic", extraction_version: "v1",
      verification_status: "unverified", geo_precision: "unknown"
    )
    @actor = NewsActor.create!(canonical_key: "nato-ca", name: "NATO", actor_type: "org")
    @claim_actor = NewsClaimActor.create!(
      news_claim: @claim, news_actor: @actor, role: "subject", position: 1
    )
  end

  test "valid creation" do
    assert @claim_actor.persisted?
  end

  test "role is required" do
    r = NewsClaimActor.new(news_claim: @claim, news_actor: @actor, position: 2)
    r.role = nil
    assert_not r.valid?
    assert_includes r.errors[:role], "can't be blank"
  end

  test "position is required" do
    r = NewsClaimActor.new(news_claim: @claim, news_actor: @actor, role: "object")
    r.position = nil
    assert_not r.valid?
    assert_includes r.errors[:position], "can't be blank"
  end

  test "belongs_to news_claim" do
    assert_equal @claim, @claim_actor.news_claim
  end

  test "belongs_to news_actor" do
    assert_equal @actor, @claim_actor.news_actor
  end
end
