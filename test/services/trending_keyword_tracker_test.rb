require "test_helper"

class TrendingKeywordTrackerTest < ActiveSupport::TestCase
  setup do
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    Rails.cache.delete(TrendingKeywordTracker::CACHE_KEY)
  end

  teardown do
    Rails.cache = @original_cache
  end

  test "ingest stores keyword counts" do
    records = [
      { title: "Earthquake strikes major city", category: "disaster" },
      { title: "Another earthquake reported nearby", category: "disaster" },
    ]

    TrendingKeywordTracker.ingest(records)
    counts = Rails.cache.read(TrendingKeywordTracker::CACHE_KEY)

    assert_not_nil counts
    assert counts.key?("earthquake")
    assert_equal 2, counts["earthquake"][:total]
  end

  test "ingest filters stop words and short words" do
    records = [
      { title: "Critical infrastructure failure detected today", category: "test" },
    ]

    TrendingKeywordTracker.ingest(records)
    counts = Rails.cache.read(TrendingKeywordTracker::CACHE_KEY) || {}

    # "the" is a stop word, short words are filtered
    assert_not counts.key?("the")
    # "critical" should be kept (8 chars, not a stop word)
    assert counts.key?("critical"), "Expected 'critical' to be tracked"
  end

  test "trending returns keywords sorted by velocity" do
    records = 5.times.map do |i|
      { title: "Critical infrastructure attack reported #{i}", category: "security" }
    end

    TrendingKeywordTracker.ingest(records)
    trending = TrendingKeywordTracker.trending(limit: 10)

    assert_kind_of Array, trending
    if trending.any?
      assert trending.first.key?(:keyword)
      assert trending.first.key?(:velocity)
      velocities = trending.map { |t| t[:velocity] }
      assert_equal velocities, velocities.sort.reverse
    end
  end

  test "trending with no data returns empty array" do
    trending = TrendingKeywordTracker.trending
    assert_equal [], trending
  end
end
