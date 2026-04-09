require "test_helper"

class NewsTrustScorerTest < ActiveSupport::TestCase
  test "source_reliability_for returns known reliability for wire" do
    result = NewsTrustScorer.source_reliability_for("wire")

    assert_in_delta 0.92, result, 0.01
  end

  test "source_reliability_for returns known reliability for publisher" do
    result = NewsTrustScorer.source_reliability_for("publisher")

    assert_in_delta 0.74, result, 0.01
  end

  test "source_reliability_for returns known reliability for aggregator" do
    result = NewsTrustScorer.source_reliability_for("aggregator")

    assert_in_delta 0.48, result, 0.01
  end

  test "source_reliability_for returns default for unknown kind" do
    result = NewsTrustScorer.source_reliability_for("unknown")

    assert_in_delta 0.4, result, 0.01
  end

  test "source_reliability_for blends origin source when present" do
    result = NewsTrustScorer.source_reliability_for("aggregator", "wire")

    expected = (0.48 * 0.65) + (0.92 * 0.35)
    assert_in_delta expected, result, 0.01
  end

  test "source_reliability_for ignores blank origin" do
    result = NewsTrustScorer.source_reliability_for("wire", nil)

    assert_in_delta 0.92, result, 0.01
  end

  test "verification_status_for returns unverified for aggregator" do
    assert_equal "unverified", NewsTrustScorer.verification_status_for("aggregator")
  end

  test "verification_status_for returns unverified for platform" do
    assert_equal "unverified", NewsTrustScorer.verification_status_for("platform")
  end

  test "verification_status_for returns single_source for wire" do
    assert_equal "single_source", NewsTrustScorer.verification_status_for("wire")
  end

  test "verification_status_for returns single_source for publisher" do
    assert_equal "single_source", NewsTrustScorer.verification_status_for("publisher")
  end

  test "geo_precision_for returns point when lat and lng present" do
    result = NewsTrustScorer.geo_precision_for(location_name: "Berlin", latitude: 52.5, longitude: 13.4)

    assert_equal "point", result
  end

  test "geo_precision_for returns unknown when no location info" do
    result = NewsTrustScorer.geo_precision_for(location_name: nil, latitude: nil, longitude: nil)

    assert_equal "unknown", result
  end

  test "geo_precision_for returns unknown for blank location" do
    result = NewsTrustScorer.geo_precision_for(location_name: "  ", latitude: nil, longitude: nil)

    assert_equal "unknown", result
  end

  test "geo_precision_for returns country for country name" do
    result = NewsTrustScorer.geo_precision_for(location_name: "Ukraine", latitude: nil, longitude: nil)

    assert_equal "country", result
  end

  test "geo_precision_for returns named_area for city name" do
    result = NewsTrustScorer.geo_precision_for(location_name: "Mariupol", latitude: nil, longitude: nil)

    assert_equal "named_area", result
  end

  test "overall_confidence computes weighted average" do
    result = NewsTrustScorer.overall_confidence(
      event_confidence: 1.0,
      actor_confidence: 1.0,
      extraction_confidence: 1.0,
      source_reliability: 1.0,
      geo_confidence: 1.0,
    )

    # All 1.0, weighted sum = 1.0, capped at 0.99
    assert_in_delta 0.99, result, 0.01
  end

  test "overall_confidence caps at 0.99" do
    result = NewsTrustScorer.overall_confidence(
      event_confidence: 1.0,
      actor_confidence: 1.0,
      extraction_confidence: 1.0,
      source_reliability: 1.0,
      geo_confidence: 1.0,
    )

    assert result <= 0.99
  end

  test "overall_confidence returns 0 for all zeros" do
    result = NewsTrustScorer.overall_confidence(
      event_confidence: 0.0,
      actor_confidence: 0.0,
      extraction_confidence: 0.0,
      source_reliability: 0.0,
      geo_confidence: 0.0,
    )

    assert_in_delta 0.0, result, 0.01
  end

  test "claim_attributes returns expected keys" do
    result = NewsTrustScorer.claim_attributes(
      source_kind: "wire",
      publisher_name: "AP",
      publisher_domain: "apnews.com",
      origin_source_name: nil,
      origin_source_kind: nil,
      origin_source_domain: nil,
      location_name: "Kyiv",
      latitude: 50.45,
      longitude: 30.52,
      event_id: "ev-1",
      event_title: "Test Event",
      canonical_url: "https://example.com/article",
      extraction: { event_confidence: 0.9, actor_confidence: 0.8, extraction_confidence: 0.85, metadata: {} },
      claim_text: "Something happened",
      published_at: Time.current,
    )

    assert result.key?(:event_confidence)
    assert result.key?(:actor_confidence)
    assert result.key?(:extraction_confidence)
    assert result.key?(:source_reliability)
    assert result.key?(:geo_precision)
    assert result.key?(:geo_confidence)
    assert result.key?(:verification_status)
    assert result.key?(:confidence)
    assert result.key?(:provenance)
  end

  test "claim_attributes truncates claim_text in provenance" do
    long_text = "x" * 500
    result = NewsTrustScorer.claim_attributes(
      source_kind: "wire",
      publisher_name: "AP",
      publisher_domain: "apnews.com",
      origin_source_name: nil,
      origin_source_kind: nil,
      origin_source_domain: nil,
      location_name: nil,
      latitude: nil,
      longitude: nil,
      event_id: "ev-2",
      event_title: "Test",
      canonical_url: "https://example.com",
      extraction: { event_confidence: 0.5, actor_confidence: 0.5, extraction_confidence: 0.5, metadata: {} },
      claim_text: long_text,
      published_at: Time.current,
    )

    assert result[:provenance]["claim_text_excerpt"].length <= 280
  end
end
