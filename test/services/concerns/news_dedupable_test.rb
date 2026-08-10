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

  test "dedup_by_title removes a publisher's repeated headline" do
    records = [
      { title: "Major earthquake hits Turkey", url: "https://bbc.com/a" },
      { title: "Major Earthquake Hits Turkey!", url: "https://bbc.com/b" },
      { title: "Flooding in Germany kills 5", url: "https://bbc.com/c" },
    ]
    result = @tester.dedup_by_title(records)
    assert_equal 2, result.size
  end

  # The corroboration case: the same story carried by different newsrooms must
  # survive ingest so NewsStoryClusterer can collapse it into one cluster and
  # count the sources. Suppressing it here is what left clusters single_source.
  test "dedup_by_title keeps the same headline from different publishers" do
    records = [
      { title: "Major earthquake hits Turkey", url: "https://bbc.com/a" },
      { title: "Major earthquake hits Turkey", url: "https://reuters.com/b" },
      { title: "Major earthquake hits Turkey", url: "https://apnews.com/c" },
    ]
    result = @tester.dedup_by_title(records)
    assert_equal 3, result.size, "syndicated copies must reach the clusterer"
  end

  test "dedup_by_title suppresses against the same publisher's existing events" do
    existing = [["https://bbc.com/old", "Major earthquake hits Turkey"]]
    records = [
      { title: "Major earthquake hits Turkey again", url: "https://bbc.com/new" },
      { title: "Major earthquake hits Turkey again", url: "https://reuters.com/new" },
      { title: "Completely different story about space", url: "https://bbc.com/space" },
    ]
    result = @tester.dedup_by_title(records, existing: existing)

    assert result.any? { |r| r[:title].include?("space") }
    assert result.none? { |r| r[:url] == "https://bbc.com/new" }, "same publisher repeat is suppressed"
    assert result.any? { |r| r[:url] == "https://reuters.com/new" }, "other publisher is kept"
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
