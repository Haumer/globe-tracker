require "test_helper"

class StrikeArcExtractorTest < ActiveSupport::TestCase
  test "extracts directional arc from headline" do
    arcs = StrikeArcExtractor.extract(["Israel strikes Iran nuclear facility"])
    assert arcs.any?
    arc = arcs.first
    assert_equal "Israel", arc[:from_name]
    assert_equal "Iran", arc[:to_name]
  end

  test "extracts multiple arcs from multiple headlines" do
    headlines = [
      "Israel strikes Iran nuclear facility",
      "Iran hits Tel Aviv with missiles",
      "Russia strikes Kyiv with drones",
    ]
    arcs = StrikeArcExtractor.extract(headlines)
    names = arcs.map { |a| "#{a[:from_name]}→#{a[:to_name]}" }
    assert_includes names, "Israel→Iran"
    assert_includes names, "Russia→Kyiv"
  end

  test "returns empty for non-conflict headlines" do
    arcs = StrikeArcExtractor.extract(["Apple launches new iPhone", "Weather is nice today"])
    assert_empty arcs
  end

  test "counts duplicate arcs" do
    headlines = 5.times.map { "Israel strikes Tehran" }
    arcs = StrikeArcExtractor.extract(headlines)
    arc = arcs.find { |a| a[:from_name] == "Israel" }
    assert_equal 5, arc[:count]
  end

  test "limits to MAX_ARCS results" do
    assert_equal 30, StrikeArcExtractor::MAX_ARCS
  end
end
