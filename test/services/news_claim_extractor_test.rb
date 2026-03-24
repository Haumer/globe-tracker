require "test_helper"

class NewsClaimExtractorTest < ActiveSupport::TestCase
  test "extracts initiator and target for military headlines" do
    result = NewsClaimExtractor.extract("Israel strikes Iran nuclear sites")

    assert_not_nil result
    assert_equal "conflict", result[:event_family]
    assert_equal "ground_operation", result[:event_type]
    assert_equal [ "Israel", "Iran" ], result[:actors].map { |actor| actor[:name] }
    assert_equal [ "initiator", "target" ], result[:actors].map { |actor| actor[:role] }
  end

  test "extracts participants for diplomacy headlines" do
    result = NewsClaimExtractor.extract("Iran-U.S. peace talks resume in Oman")

    assert_not_nil result
    assert_equal "diplomacy", result[:event_family]
    assert_equal "negotiation", result[:event_type]
    assert_equal [ "Iran", "United States", "Oman" ], result[:actors].map { |actor| actor[:name] }
    assert_equal [ "participant", "participant", "host" ], result[:actors].map { |actor| actor[:role] }
  end

  test "extracts agreements as diplomatic claims" do
    result = NewsClaimExtractor.extract("US, India close to finalising critical minerals pact")

    assert_not_nil result
    assert_equal "diplomacy", result[:event_family]
    assert_equal "agreement", result[:event_type]
    assert_equal [ "United States", "India" ], result[:actors].map { |actor| actor[:name] }
  end

  test "extracts sanctions as directional claims" do
    result = NewsClaimExtractor.extract("U.S. sanctions Iran over missile program")

    assert_not_nil result
    assert_equal "economy", result[:event_family]
    assert_equal "sanction_action", result[:event_type]
    assert_equal "United States", result[:actors].first[:name]
    assert_equal "initiator", result[:actors].first[:role]
    assert_equal "Iran", result[:actors].second[:name]
    assert_equal "target", result[:actors].second[:role]
  end

  test "extracts ceasefire from statements when the event term is present" do
    result = NewsClaimExtractor.extract("Hamas says ceasefire proposal is under review")

    assert_not_nil result
    assert_equal "conflict", result[:event_family]
    assert_equal "ceasefire", result[:event_type]
    assert_equal [ "Hamas" ], result[:actors].map { |actor| actor[:name] }
    assert_equal [ "subject" ], result[:actors].map { |actor| actor[:role] }
  end

  test "uses summary text when the headline is too thin" do
    result = NewsClaimExtractor.extract(
      "Delegations regroup",
      summary: "Iran and the United States will meet next week in Muscat for talks."
    )

    assert_not_nil result
    assert_equal "diplomacy", result[:event_family]
    assert_equal "negotiation", result[:event_type]
    assert_equal [ "Iran", "United States", "Oman" ], result[:actors].map { |actor| actor[:name] }
    assert_equal "summary", result[:metadata]["matched_on"]
  end

  test "extracts cyberattack claims" do
    result = NewsClaimExtractor.extract("Taiwan says China-linked hackers breached ministry systems")

    assert_not_nil result
    assert_equal "cyber", result[:event_family]
    assert_equal "cyberattack", result[:event_type]
    assert_equal [ "China", "Taiwan" ], result[:actors].map { |actor| actor[:name] }
    assert_equal [ "initiator", "target" ], result[:actors].first(2).map { |actor| actor[:role] }
  end

  test "extracts diplomatic contact claims" do
    result = NewsClaimExtractor.extract("Cuban foreign minister speaks to Chinese, Russian counterparts")

    assert_not_nil result
    assert_equal "diplomacy", result[:event_family]
    assert_equal "diplomatic_contact", result[:event_type]
    assert_equal [ "Cuba", "China", "Russia" ], result[:actors].map { |actor| actor[:name] }
  end

  test "returns nil when no actor can be identified" do
    assert_nil NewsClaimExtractor.extract("Markets tumble after surprise rate move")
  end
end
