require "test_helper"

class NewsClaimTest < ActiveSupport::TestCase
  setup do
    @source = NewsSource.create!(canonical_key: "ap-news", name: "AP News", source_kind: "publisher")
    @article = NewsArticle.create!(
      news_source: @source, url: "https://ap.com/1", canonical_url: "https://ap.com/1",
      normalization_status: "normalized", content_scope: "core"
    )
    @claim = NewsClaim.create!(
      news_article: @article,
      event_type: "military_strike",
      event_family: "conflict",
      extraction_method: "heuristic",
      extraction_version: "headline_rules_v1",
      verification_status: "unverified",
      geo_precision: "city"
    )
  end

  test "valid creation" do
    assert @claim.persisted?
  end

  test "event_type is required" do
    r = NewsClaim.new(news_article: @article, event_family: "conflict", extraction_method: "heuristic", extraction_version: "v1", verification_status: "unverified", geo_precision: "unknown")
    r.event_type = nil
    assert_not r.valid?
    assert_includes r.errors[:event_type], "can't be blank"
  end

  test "event_family is required" do
    r = NewsClaim.new(news_article: @article, event_type: "strike", extraction_method: "heuristic", extraction_version: "v1", verification_status: "unverified", geo_precision: "unknown")
    r.event_family = nil
    assert_not r.valid?
    assert_includes r.errors[:event_family], "can't be blank"
  end

  test "belongs_to news_article" do
    assert_equal @article, @claim.news_article
  end

  test "has_many news_claim_actors" do
    assert_respond_to @claim, :news_claim_actors
  end

  test "has_many news_actors through news_claim_actors" do
    assert_respond_to @claim, :news_actors
  end
end
