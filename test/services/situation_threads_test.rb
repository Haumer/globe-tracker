require "test_helper"

class SituationThreadsTest < ActiveSupport::TestCase
  def member(headline:, type: nil, family: nil, articles: 1, seen: "2026-08-20T10:00:00Z", cluster: nil)
    { cluster_id: cluster || headline.hash.abs,
      headline: headline,
      article_count: articles,
      last_seen_at: seen,
      claim: type ? { type: type, family: family } : nil,
      event_type: type,
      event_family: family }
  end

  test "a saga groups into threads, context trailing, kinetic and talks split" do
    members = [
      member(headline: "Missile hits tanker", type: "missile_attack", family: "conflict"),
      member(headline: "Second vessel attacked", type: "attack", family: "conflict"),
      member(headline: "Deal near, sources say", type: "negotiation", family: "diplomacy"),
      member(headline: "MoU signed on routes", type: "agreement", family: "diplomacy", seen: "2026-08-21T09:00:00Z"),
      member(headline: "Why the strait matters", type: nil, family: nil),
      member(headline: "Gas prices surge", type: "market_move", family: "economy"),
    ]

    threads = SituationThreads.call(members)

    assert_equal %w[kinetic talks context], threads.map { |t| t[:key] }
    talks = threads.find { |t| t[:key] == "talks" }
    assert_equal 2, talks[:story_count]
    assert_equal "2026-08-21T09:00:00Z", talks[:last_seen_at]
    assert members.all? { |m| m[:thread].present? }
  end

  test "an unknown type falls back to its family before falling to context" do
    members = [
      member(headline: "A", type: "weird_new_type", family: "conflict"),
      member(headline: "B", type: "skirmish_x", family: "conflict"),
      member(headline: "C", type: "negotiation", family: "diplomacy"),
      member(headline: "D", type: "agreement", family: "diplomacy"),
      member(headline: "E", type: "statement", family: "diplomacy"),
    ]

    threads = SituationThreads.call(members)
    assert_equal 2, threads.find { |t| t[:key] == "kinetic" }[:story_count]
  end

  test "duplicate headlines fold onto the strongest row and vanish from counts" do
    members = [
      member(headline: ".iran Makes New Demands", articles: 1, cluster: 1, type: "statement", family: "diplomacy"),
      member(headline: ".iran Makes New Demands", articles: 3, cluster: 2, type: "statement", family: "diplomacy"),
      member(headline: ".iran makes new demands!", articles: 0, cluster: 3, type: "statement", family: "diplomacy"),
      member(headline: "Strike on port", type: "airstrike", family: "conflict", cluster: 4),
      member(headline: "Second strike", type: "airstrike", family: "conflict", cluster: 5),
      member(headline: "Talks resume", type: "negotiation", family: "diplomacy", cluster: 6),
      member(headline: "Ceasefire floated", type: "ceasefire", family: "diplomacy", cluster: 7),
    ]

    threads = SituationThreads.call(members)

    survivor = members.find { |m| m[:cluster_id] == 2 }
    assert_equal 2, survivor[:duplicates]
    assert_equal [ 2, 2 ], members.select { |m| m[:duplicate_of] }.map { |m| m[:duplicate_of] }
    talks = threads.find { |t| t[:key] == "talks" }
    assert_equal 3, talks[:story_count], "folded duplicates leave the survivor and the distinct stories"
  end

  test "thin or single-thread situations return nil but still fold duplicates" do
    thin = [
      member(headline: "One", type: "airstrike", family: "conflict"),
      member(headline: "One", type: "airstrike", family: "conflict", articles: 2, cluster: 9),
      member(headline: "Two", type: "attack", family: "conflict"),
    ]
    assert_nil SituationThreads.call(thin)
    assert thin.any? { |m| m[:duplicate_of] }

    single = (1..6).map { |i| member(headline: "Strike #{i}", type: "airstrike", family: "conflict", cluster: i) }
    assert_nil SituationThreads.call(single)
  end

  test "blank headlines never fold into each other" do
    members = [
      member(headline: nil, type: "airstrike", family: "conflict", cluster: 1),
      member(headline: nil, type: "attack", family: "conflict", cluster: 2),
      member(headline: "Talks", type: "negotiation", family: "diplomacy", cluster: 3),
      member(headline: "Deal", type: "agreement", family: "diplomacy", cluster: 4),
      member(headline: "Aid in", type: "aid_delivery", family: "aid", cluster: 5),
    ]

    SituationThreads.call(members)
    assert members.none? { |m| m[:duplicate_of] }
  end
end
