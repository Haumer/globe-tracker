require "test_helper"

class NewsScopeClassifierTest < ActiveSupport::TestCase
  test "classifies conflict headlines as core" do
    result = NewsScopeClassifier.classify(
      title: "Israel launches missile strike on Iran",
      summary: nil,
      category: "conflict"
    )

    assert_equal "core", result[:content_scope]
  end

  test "classifies sanctions and diplomacy as adjacent" do
    result = NewsScopeClassifier.classify(
      title: "U.S. sanctions Iran as talks resume in Oman",
      summary: nil,
      category: "diplomacy"
    )

    assert_equal "adjacent", result[:content_scope]
  end

  test "classifies recipes as out of scope" do
    result = NewsScopeClassifier.classify(
      title: "Best pasta recipes for a quick weeknight dinner",
      summary: "Chef tips for cooking at home",
      category: "other"
    )

    assert_equal "out_of_scope", result[:content_scope]
  end

  test "classifies celebrity gossip as out of scope" do
    result = NewsScopeClassifier.classify(
      title: "Celebrity feud explodes after red carpet interview",
      summary: nil,
      category: "other"
    )

    assert_equal "out_of_scope", result[:content_scope]
  end

  test "matches multi word geopolitical and sports phrases" do
    adjacent = NewsScopeClassifier.classify(
      title: "White House says prime minister will visit next week",
      summary: nil,
      category: "other"
    )
    out_of_scope = NewsScopeClassifier.classify(
      title: "Super Bowl box office ads dominate celebrity coverage",
      summary: nil,
      category: "other"
    )

    assert_equal "adjacent", adjacent[:content_scope]
    assert_equal "out_of_scope", out_of_scope[:content_scope]
  end

  test "classifies location only junk as out of scope" do
    result = NewsScopeClassifier.classify(
      title: "Washington, Washington, United States",
      summary: nil,
      category: nil
    )

    assert_equal "out_of_scope", result[:content_scope]
    assert_equal "pattern:location_only", result[:scope_reason]
  end

  test "classifies obvious spam as out of scope" do
    result = NewsScopeClassifier.classify(
      title: "Zodiac Local casino casino bgo sign up bonus Canada Review: $1 playing with $20!",
      summary: nil,
      category: nil
    )

    assert_equal "out_of_scope", result[:content_scope]
  end
end
