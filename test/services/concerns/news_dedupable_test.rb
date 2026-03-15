require "test_helper"

class NewsDedupableTest < ActiveSupport::TestCase
  class DedupTester
    include NewsDedupable
    public :normalize_title, :dedup_by_title, :similar?, :similarity_scores
  end

  setup do
    @tester = DedupTester.new
  end

  test "normalize_title downcases and removes punctuation" do
    result = @tester.normalize_title("Breaking: War in Ukraine!")
    assert_includes result, "breaking"
    assert_includes result, "war"
    assert_includes result, "ukraine"
    assert_not_includes result, ":"
    assert_not_includes result, "!"
  end

  test "normalize_title removes short words" do
    result = @tester.normalize_title("A war in a land")
    assert_not_includes result, "a"
    assert_includes result, "war"
  end

  test "dedup_by_title removes duplicate titles" do
    records = [
      { title: "Major earthquake hits Turkey" },
      { title: "Major Earthquake Hits Turkey!" },
      { title: "Flooding in Germany kills 5" },
    ]
    result = @tester.dedup_by_title(records)
    assert_equal 2, result.size
  end

  test "dedup_by_title respects existing_titles" do
    existing = [@tester.normalize_title("Major earthquake hits Turkey")]
    records = [
      { title: "Major earthquake hits Turkey again" },
      { title: "Completely different story about space" },
    ]
    result = @tester.dedup_by_title(records, existing_titles: existing)
    assert result.any? { |r| r[:title].include?("space") }
  end

  test "similar? returns true for identical titles" do
    a = @tester.normalize_title("Ukraine conflict escalates today")
    b = @tester.normalize_title("Ukraine conflict escalates today")
    assert @tester.similar?(a, b)
  end

  test "similar? returns false for unrelated titles" do
    a = @tester.normalize_title("Ukraine conflict escalates sharply")
    b = @tester.normalize_title("Apple releases new iPhone model")
    assert_not @tester.similar?(a, b)
  end

  test "similar? returns false for empty sets" do
    assert_not @tester.similar?(Set.new, Set.new(["word"]))
  end
end
