require "test_helper"

class NewsEnrichmentServiceTest < ActiveSupport::TestCase
  test "resolve_ai_location finds city coordinates" do
    lat, lng = NewsEnrichmentService.send(:resolve_ai_location, "Baghdad", "Iraq")
    assert_in_delta 33.31, lat, 0.5
    assert_in_delta 44.37, lng, 0.5
  end

  test "resolve_ai_location falls back to country when city unknown" do
    lat, lng = NewsEnrichmentService.send(:resolve_ai_location, "UnknownVille", "Japan")
    assert_in_delta 35.7, lat, 1.0
    assert_in_delta 139.7, lng, 1.0
  end

  test "resolve_ai_location returns nil for unknown location" do
    result = NewsEnrichmentService.send(:resolve_ai_location, nil, nil)
    assert_nil result
  end

  test "parse_json_array extracts array from markdown fences" do
    text = "```json\n[{\"i\": 1, \"city\": \"Gaza\"}]\n```"
    result = NewsEnrichmentService.send(:parse_json_array, text)
    assert_equal 1, result.size
    assert_equal "Gaza", result.first["city"]
  end

  test "parse_json_array handles plain JSON" do
    text = '[{"i": 1, "cluster": "test-event"}]'
    result = NewsEnrichmentService.send(:parse_json_array, text)
    assert_equal 1, result.size
  end

  test "parse_json_array returns nil for invalid JSON" do
    assert_nil NewsEnrichmentService.send(:parse_json_array, "not json")
  end

  test "enrich_recent returns 0 when no unenriched articles" do
    assert_equal 0, NewsEnrichmentService.enrich_recent(limit: 10)
  end

  test "constants are defined" do
    assert_equal 50, NewsEnrichmentService::BATCH_SIZE
    assert_equal "gpt-4.1-nano", NewsEnrichmentService::GEOCODE_MODEL
    assert_includes NewsEnrichmentService::CLUSTER_MODEL, "claude"
  end
end
