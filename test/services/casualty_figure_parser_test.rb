require "test_helper"

class CasualtyFigureParserTest < ActiveSupport::TestCase
  test "reads the classic breaking-news phrasings" do
    figures = CasualtyFigureParser.parse("Bomb attack kills at least 69, injures 143 in market")

    assert_equal [
      { "kind" => "killed", "value" => 69, "qualifier" => "at_least" },
      { "kind" => "injured", "value" => 143 },
    ], figures
  end

  test "death toll revisions phrase the number after the verb" do
    assert_equal [ { "kind" => "killed", "value" => 111 } ],
      CasualtyFigureParser.parse("Death toll rises to 111 after market bombing")
    assert_equal [ { "kind" => "killed", "value" => 1200, "qualifier" => "about" } ],
      CasualtyFigureParser.parse("Quake death toll hits about 1,200")
  end

  test "number-first phrasings with and without a noun" do
    assert_equal [ { "kind" => "killed", "value" => 12 } ],
      CasualtyFigureParser.parse("12 people killed in strike on depot")
    assert_equal [ { "kind" => "killed", "value" => 8, "qualifier" => "at_least" } ],
      CasualtyFigureParser.parse("At least 8 dead as floods sweep valley")
    assert_equal [ { "kind" => "missing", "value" => 30 } ],
      CasualtyFigureParser.parse("30 missing after ferry capsizes")
  end

  test "one figure per kind, keeping the revision over the early number" do
    figures = CasualtyFigureParser.parse("Strike kills 12; death toll later rises to 15")

    assert_equal [ { "kind" => "killed", "value" => 15 } ], figures
  end

  test "wordy tolls produce nothing rather than an invented number" do
    assert_equal [], CasualtyFigureParser.parse("Dozens feared dead in mine collapse")
    assert_equal [], CasualtyFigureParser.parse("Markets fall as talks stall")
    assert_equal [], CasualtyFigureParser.parse(nil)
  end
end
