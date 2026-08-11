require "test_helper"

class ThreatClassifierTest < ActiveSupport::TestCase
  test "classify conflict headline" do
    result = ThreatClassifier.classify("Missile strike hits military base")
    assert_equal "conflict", result[:category]
    assert_includes %w[high critical], result[:threat]
    assert result[:tone] < 0
  end

  test "classify terror headline" do
    result = ThreatClassifier.classify("Terrorist bombing kills dozens")
    assert_equal "terror", result[:category]
    assert_equal "critical", result[:threat]
    assert result[:tone] <= -5
  end

  test "classify disaster headline" do
    result = ThreatClassifier.classify("Powerful earthquake devastates coastal region")
    assert_equal "disaster", result[:category]
    assert_equal "high", result[:threat]
  end

  test "classify returns other for unmatched headline" do
    result = ThreatClassifier.classify("New art exhibit opens at local gallery")
    assert_equal "other", result[:category]
    assert_equal "info", result[:threat]
    assert_equal 0.0, result[:tone]
    assert_empty result[:keywords]
  end

  test "historical pattern downgrades to info" do
    result = ThreatClassifier.classify("The bombing campaign in 2003 was devastating")
    assert_equal "info", result[:threat]
  end

  test "softener near conflict downgrades threat" do
    result = ThreatClassifier.classify("Peace talks aim to end the conflict and fighting")
    assert_not_equal "critical", result[:threat]
  end

  test "critical target escalation" do
    result = ThreatClassifier.classify("Russia launches missile strike on NATO forces")
    assert_equal "critical", result[:threat]
    assert result[:tone] <= -7
  end

  test "tone_level returns correct levels" do
    assert_equal "critical", ThreatClassifier.tone_level(-6)
    assert_equal "negative", ThreatClassifier.tone_level(-3)
    assert_equal "neutral", ThreatClassifier.tone_level(0)
    assert_equal "positive", ThreatClassifier.tone_level(3)
  end

  test "normalize_category accepts the canonical vocabulary" do
    ThreatClassifier::CATEGORY_NAMES.each do |name|
      assert_equal name, ThreatClassifier.normalize_category(name)
    end
  end

  test "normalize_category folds the spellings the AI enricher used to emit" do
    assert_equal "economy", ThreatClassifier.normalize_category("economic")
    assert_equal "politics", ThreatClassifier.normalize_category("political")
    assert_equal "politics", ThreatClassifier.normalize_category("poiltics")
  end

  test "normalize_category is case and whitespace insensitive" do
    assert_equal "conflict", ThreatClassifier.normalize_category("  Conflict ")
  end

  test "normalize_category returns nil for values it cannot place" do
    assert_nil ThreatClassifier.normalize_category("hamilton")
    assert_nil ThreatClassifier.normalize_category("")
    assert_nil ThreatClassifier.normalize_category(nil)
  end

  test "every classified category is part of the canonical vocabulary" do
    ThreatClassifier::CATEGORIES.each do |category|
      assert_includes ThreatClassifier::CATEGORY_NAMES, category[:name]
    end
  end

  test "categorize_themes from GDELT themes" do
    assert_equal "conflict", ThreatClassifier.categorize_themes(["ARMEDCONFLICT"])
    assert_equal "unrest", ThreatClassifier.categorize_themes(["PROTEST"])
    assert_equal "disaster", ThreatClassifier.categorize_themes(["EARTHQUAKE"])
    assert_equal "health", ThreatClassifier.categorize_themes(["PANDEMIC"])
    assert_equal "economy", ThreatClassifier.categorize_themes(["ECON_RECESSION"])
    assert_equal "diplomacy", ThreatClassifier.categorize_themes(["PEACE"])
    assert_equal "other", ThreatClassifier.categorize_themes(["SPORTS"])
  end
end
