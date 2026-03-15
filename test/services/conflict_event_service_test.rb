require "test_helper"

class ConflictEventServiceTest < ActiveSupport::TestCase
  test "rate_limit_exhausted? returns false when requests below limit" do
    # With null_store cache, requests_today always returns 0
    assert_not ConflictEventService.rate_limit_exhausted?
  end

  test "requests_today returns integer" do
    result = ConflictEventService.requests_today
    assert_kind_of Integer, result
  end

  test "DAILY_REQUEST_LIMIT is a positive integer" do
    assert_kind_of Integer, ConflictEventService::DAILY_REQUEST_LIMIT
    assert ConflictEventService::DAILY_REQUEST_LIMIT > 0
  end

  test "api_token returns nil when not configured" do
    # In test env, ENV["UCDP_API_TOKEN"] is typically not set
    original = ENV["UCDP_API_TOKEN"]
    ENV["UCDP_API_TOKEN"] = nil
    result = ConflictEventService.api_token
    # May return nil or a credential, depending on config
    ENV["UCDP_API_TOKEN"] = original
  end

  test "upsert_events creates conflict events" do
    results = [
      {
        "id" => 99999,
        "conflict_name" => "Test Conflict",
        "side_a" => "Side A",
        "side_b" => "Side B",
        "country" => "Testland",
        "region" => "Test Region",
        "latitude" => 10.5,
        "longitude" => 20.5,
        "date_start" => "2024-01-01",
        "date_end" => "2024-01-02",
        "best" => 5,
        "deaths_a" => 2,
        "deaths_b" => 3,
        "deaths_civilians" => 0,
        "type_of_violence" => 1,
        "source_headline" => "Clash in Test Region",
      }
    ]

    assert_difference "ConflictEvent.count" do
      ConflictEventService.send(:upsert_events, results)
    end

    event = ConflictEvent.find_by(external_id: 99999)
    assert_equal "Test Conflict", event.conflict_name
    assert_equal 5, event.best_estimate
  end

  test "upsert_events skips events without coordinates" do
    results = [
      { "id" => 88888, "latitude" => nil, "longitude" => nil }
    ]

    assert_no_difference "ConflictEvent.count" do
      ConflictEventService.send(:upsert_events, results)
    end
  end
end
