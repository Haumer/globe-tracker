require "test_helper"

class NewsClaimTypeBackfillServiceTest < ActiveSupport::TestCase
  setup do
    @source = NewsSource.create!(
      canonical_key: "publisher:example.com", name: "Example",
      source_kind: "publisher", publisher_domain: "example.com"
    )
  end

  def article(title, scope: "adjacent", slug: title.parameterize)
    NewsArticle.create!(
      news_source: @source,
      url: "https://example.com/#{slug}",
      canonical_url: "https://example.com/#{slug}",
      title: title,
      content_scope: scope,
      published_at: Time.utc(2026, 3, 24, 10, 0, 0),
      fetched_at: Time.utc(2026, 3, 24, 10, 5, 0)
    )
  end

  def general_claim(article, event_type: "actor_mention")
    NewsClaim.create!(
      news_article: article,
      event_family: "general",
      event_type: event_type,
      claim_text: article.title,
      confidence: 0.4,
      extraction_method: "heuristic",
      extraction_version: "headline_summary_rules_v2",
      primary: true,
      metadata: { "matched_on" => nil },
      published_at: article.published_at
    )
  end

  def stub(*replies)
    queue = replies.dup
    ->(_prompt) { queue.shift }
  end

  def index_of(event_type)
    NewsClaimTypeResolver::CATALOG.index { |pair| pair[:event_type] == event_type }
  end

  test "writes the resolved family and type and keeps what the rules produced" do
    claim = general_claim(article("Explosions reported across Isfahan province"))

    stats = NewsClaimTypeBackfillService.run(
      client: stub(%({"answers": [{"n": 1, "choice": #{index_of('airstrike')}}]}))
    )

    claim.reload
    assert_equal "conflict", claim.event_family
    assert_equal "airstrike", claim.event_type
    assert_equal "model", claim.extraction_method
    assert_equal "claim_type_resolver_v1", claim.extraction_version
    assert_equal "general", claim.metadata.dig("resolved_from", "event_family")
    assert_equal "actor_mention", claim.metadata.dig("resolved_from", "event_type")
    # The extractor's own metadata survives the merge.
    assert claim.metadata.key?("matched_on")

    assert_equal 1, stats[:assigned]
    assert_equal({ "conflict" => 1 }, stats[:families])
  end

  test "a dry run reports what it would write and writes nothing" do
    claim = general_claim(article("River bursts its banks in Punjab"))

    stats = NewsClaimTypeBackfillService.run(
      dry_run: true,
      client: stub(%({"answers": [{"n": 1, "choice": #{index_of('flood')}}]}))
    )

    assert_equal "general", claim.reload.event_family
    assert_equal 1, stats[:assigned]
    assert_equal({ "disaster" => 1 }, stats[:families])
  end

  # Not reached is not a decision. The claim has to be left exactly as the rules
  # left it so a later run can pick it up, and the count has to show.
  test "an unreachable model leaves the claim alone and is counted separately" do
    claim = general_claim(article("Something happened somewhere today"))

    stats = NewsClaimTypeBackfillService.run(client: ->(_) { nil })

    claim.reload
    assert_equal "general", claim.event_family
    assert_equal "heuristic", claim.extraction_method
    assert_equal 1, stats[:unreachable]
    assert_equal 0, stats[:assigned]
    assert_equal 0, stats[:none]
  end

  test "none leaves the claim alone and is counted apart from unreachable" do
    claim = general_claim(article("Why the Gulf still misreads Washington"))

    stats = NewsClaimTypeBackfillService.run(client: stub('{"answers": [{"n": 1, "choice": null}]}'))

    assert_equal "general", claim.reload.event_family
    assert_equal 1, stats[:none]
    assert_equal 0, stats[:unreachable]
  end

  test "revert restores every row the arm wrote" do
    claim = general_claim(article("Crowds gather outside the ministry"))

    NewsClaimTypeBackfillService.run(
      client: stub(%({"answers": [{"n": 1, "choice": #{index_of('protest')}}]}))
    )
    assert_equal "politics", claim.reload.event_family

    assert_equal({ reverted: 1 }, NewsClaimTypeBackfillService.revert)

    claim.reload
    assert_equal "general", claim.event_family
    assert_equal "actor_mention", claim.event_type
    assert_equal "heuristic", claim.extraction_method
    assert_equal "headline_summary_rules_v2", claim.extraction_version
    assert_not claim.metadata.key?("resolved_from")
    assert claim.metadata.key?("matched_on"), "reverting must not strip the extractor's own metadata"
  end

  # build_payload drops an out_of_scope article before it ever consults the
  # family, so classifying one spends a call on a row that cannot move.
  test "out of scope articles are not candidates" do
    general_claim(article("Best pasta recipes for a quick dinner", scope: "out_of_scope"))
    kept = general_claim(article("Quake rattles the southern coast"))

    assert_equal [ kept.id ], NewsClaimTypeBackfillService.candidates.pluck(:id)
  end

  test "claims the rules already classified are left out" do
    general_claim(article("Quake rattles the southern coast"))
    NewsClaim.create!(
      news_article: article("Israel strikes Iran nuclear sites"),
      event_family: "conflict", event_type: "airstrike",
      claim_text: "Israel strikes Iran nuclear sites", confidence: 0.9,
      extraction_method: "heuristic", extraction_version: "headline_summary_rules_v2",
      primary: true, metadata: {}, published_at: Time.utc(2026, 3, 24, 10, 0, 0)
    )

    assert_equal 1, NewsClaimTypeBackfillService.candidates.count
  end

  test "limit samples without walking the whole backlog" do
    3.times { |index| general_claim(article("Headline number #{index}", slug: "headline-#{index}")) }

    stats = NewsClaimTypeBackfillService.run(
      limit: 2, dry_run: true, client: stub('{"answers": [{"n": 1, "choice": null}, {"n": 2, "choice": null}]}')
    )

    assert_equal 2, stats[:candidates]
  end

  # The rules misfire on 56.5% of the claims they DO match, so scope: :all sends
  # those through the model too. A wrong label is worse than none -- an
  # incompatible event_type scores 0.0 and blocks a correct merge outright.
  test "scope all classifies claims the rules already labelled" do
    rule_matched = NewsClaim.create!(
      news_article: article("Magnitude 7.4 earthquake strikes Colombia"),
      event_family: "conflict", event_type: "ground_operation",
      claim_text: "quake", confidence: 0.8,
      extraction_method: "heuristic", extraction_version: "headline_summary_rules_v2",
      primary: true, metadata: {}, published_at: Time.utc(2026, 3, 24, 10, 0, 0)
    )

    assert_not_includes NewsClaimTypeBackfillService.candidates.pluck(:id), rule_matched.id,
      "the default scope leaves rule-matched claims alone"
    assert_includes NewsClaimTypeBackfillService.candidates(scope: :all).pluck(:id), rule_matched.id

    NewsClaimTypeBackfillService.run(
      scope: :all,
      client: stub(%({"answers": [{"n": 1, "choice": #{index_of('earthquake')}}]}))
    )

    rule_matched.reload
    assert_equal "disaster", rule_matched.event_family
    assert_equal "earthquake", rule_matched.event_type
    assert_equal "ground_operation", rule_matched.metadata.dig("resolved_from", "event_type")
  end

  # The job re-runs every five minutes, so a row it already settled must not be
  # paid for twice.
  test "a claim this version already resolved is not a candidate again" do
    claim = general_claim(article("Crowds gather outside the ministry"))
    NewsClaimTypeBackfillService.run(
      client: stub(%({"answers": [{"n": 1, "choice": #{index_of('protest')}}]}))
    )

    assert_not_includes NewsClaimTypeBackfillService.candidates(scope: :all).pluck(:id), claim.id
    assert_equal 0, NewsClaimTypeBackfillService.run(scope: :all, client: ->(_) { flunk "called again" })[:candidates]
  end
end
