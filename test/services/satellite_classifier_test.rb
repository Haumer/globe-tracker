require "test_helper"

class SatelliteClassifierTest < ActiveSupport::TestCase
  test "classifies US NRO satellite" do
    result = SatelliteClassifier.classify("NROL-82")
    assert_equal "US NRO", result[:operator]
    assert_equal "reconnaissance", result[:mission_type]
  end

  test "classifies US DoD communications satellite" do
    result = SatelliteClassifier.classify("WGS-11")
    assert_equal "US DoD", result[:operator]
    assert_equal "milcomms", result[:mission_type]
  end

  test "classifies Russian military satellite" do
    result = SatelliteClassifier.classify("COSMOS 2558")
    assert_equal "Russia MoD", result[:operator]
    assert_nil result[:mission_type]
  end

  test "classifies Chinese reconnaissance satellite" do
    result = SatelliteClassifier.classify("YAOGAN-35A")
    assert_equal "China PLA", result[:operator]
    assert_equal "reconnaissance", result[:mission_type]
  end

  test "classifies UK Skynet satellite" do
    result = SatelliteClassifier.classify("SKYNET 5C")
    assert_equal "UK MoD", result[:operator]
    assert_equal "milcomms", result[:mission_type]
  end

  test "classifies French SIGINT satellite" do
    result = SatelliteClassifier.classify("CERES-1")
    assert_equal "France DGA", result[:operator]
    assert_equal "sigint", result[:mission_type]
  end

  test "classifies GLONASS as navigation" do
    result = SatelliteClassifier.classify("GLONASS-M 751")
    assert_equal "Russia", result[:operator]
    assert_equal "navigation", result[:mission_type]
  end

  test "returns nil for unknown satellite" do
    result = SatelliteClassifier.classify("STARLINK-5001")
    assert_nil result[:operator]
    assert_nil result[:mission_type]
  end

  test "returns nil for blank name" do
    result = SatelliteClassifier.classify(nil)
    assert_nil result[:operator]
    assert_nil result[:mission_type]

    result = SatelliteClassifier.classify("")
    assert_nil result[:operator]
    assert_nil result[:mission_type]
  end

  test "classify is case insensitive" do
    result = SatelliteClassifier.classify("sbirs geo-5")
    assert_equal "US DoD", result[:operator]
    assert_equal "early_warning", result[:mission_type]
  end

  test "MISSION_TYPE_LABELS contains all mission types" do
    all_types = SatelliteClassifier::MILITARY_PATTERNS.values.map(&:last).compact.uniq
    all_types.each do |mt|
      assert SatelliteClassifier::MISSION_TYPE_LABELS.key?(mt),
        "Missing label for mission_type: #{mt}"
    end
  end
end
