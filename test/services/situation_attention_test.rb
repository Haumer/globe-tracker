require "test_helper"

class SituationAttentionTest < ActiveSupport::TestCase
  NOW = Time.utc(2026, 8, 23, 12, 0, 0)

  def rows(*specs)
    specs.map { |hours_ago, source| { published_at: NOW - hours_ago.hours, source_id: source } }
  end

  test "observe counts recent reports and sources whose FIRST report is recent" do
    observation = SituationAttention.observe(
      rows([1, :a], [2, :a], [3, :b], [30, :b], [40, :c]), now: NOW
    )

    assert_equal 3, observation[:recent_articles]
    # :a is new inside the window; :b filed 30h ago first, so its 3h report is
    # an echo, not corroboration.
    assert_equal 1, observation[:recent_sources]
    assert_equal NOW - 1.hour, observation[:last_seen_at]
  end

  test "a burst above the story's own baseline flares" do
    history = (1..7).to_h { |n| [(NOW.to_date - n).iso8601, { "a" => 4, "s" => 1 }] }
    observation = SituationAttention.observe(
      rows([1, :a], [2, :b], [3, :c], [4, :d]), now: NOW
    )
    verdict = SituationAttention.assess(observation, baseline_daily: SituationAttention.baseline_daily(history, today: NOW.to_date), now: NOW)

    # Baseline 4/day expects 1 report per 6h; four reports from four fresh
    # sources is a 4x burst.
    assert_equal "flaring", verdict[:state]
    assert_operator verdict[:ratio], :>=, SituationAttention::FLARE_RATIO
  end

  test "the same volume is routine for a story that always runs this hot" do
    history = (1..7).to_h { |n| [(NOW.to_date - n).iso8601, { "a" => 40, "s" => 4 }] }
    observation = SituationAttention.observe(
      rows([1, :a], [2, :b], [3, :c], [4, :d]), now: NOW
    )
    verdict = SituationAttention.assess(observation, baseline_daily: SituationAttention.baseline_daily(history, today: NOW.to_date), now: NOW)

    assert_equal "active", verdict[:state], "four reports against a 40/day baseline is Tuesday"
  end

  test "volume without corroboration never flares" do
    observation = SituationAttention.observe(
      rows([1, :wire], [2, :wire], [3, :wire], [4, :wire], [5, :wire]), now: NOW
    )
    verdict = SituationAttention.assess(observation, baseline_daily: SituationAttention::BASELINE_FLOOR_PER_DAY, now: NOW)

    assert_equal "active", verdict[:state], "one wire echoing is volume, not attention"
  end

  test "a young story's first corroboration wave flares by construction" do
    observation = SituationAttention.observe(
      rows([1, :a], [2, :b], [3, :c]), now: NOW
    )
    verdict = SituationAttention.assess(
      observation,
      baseline_daily: SituationAttention.baseline_daily({}, today: NOW.to_date),
      now: NOW
    )

    assert_equal "flaring", verdict[:state]
  end

  test "silence goes quiet" do
    observation = SituationAttention.observe(rows([30, :a]), now: NOW)
    verdict = SituationAttention.assess(observation, baseline_daily: 2.0, now: NOW)

    assert_equal "quiet", verdict[:state]
  end

  test "daily tallies bucket by UTC date and count first-report sources per day" do
    tallies = SituationAttention.daily_tallies(
      rows([1, :a], [2, :b], [26, :b]), now: NOW
    )

    assert_equal({ "a" => 2, "s" => 1 }, tallies[NOW.to_date.iso8601], ":b's first report was yesterday")
    assert_equal({ "a" => 1, "s" => 1 }, tallies[(NOW.to_date - 1).iso8601])
  end

  test "baseline excludes today and floors at the stand-in rate" do
    history = { NOW.to_date.iso8601 => { "a" => 90, "s" => 9 },
                (NOW.to_date - 1).iso8601 => { "a" => 1, "s" => 1 } }

    assert_equal SituationAttention::BASELINE_FLOOR_PER_DAY,
                 SituationAttention.baseline_daily(history, today: NOW.to_date),
                 "today's burst must not raise the baseline it is judged against"
  end
end
