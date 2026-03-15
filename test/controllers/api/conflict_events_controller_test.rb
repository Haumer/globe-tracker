require "test_helper"

class Api::ConflictEventsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @event = ConflictEvent.create!(
      external_id: 10001,
      conflict_name: "Test Conflict",
      side_a: "Government",
      side_b: "Rebels",
      country: "TestCountry",
      latitude: 15.0,
      longitude: 45.0,
      date_start: 3.days.ago,
      type_of_violence: 1,
      best_estimate: 10
    )
  end

  test "GET /api/conflict_events returns JSON array" do
    get "/api/conflict_events"
    assert_response :success

    data = JSON.parse(response.body)
    assert_kind_of Array, data
  end

  test "response contains expected fields" do
    get "/api/conflict_events"
    data = JSON.parse(response.body)
    event = data.find { |e| e["conflict"] == "Test Conflict" }

    assert_not_nil event
    assert_equal "Government", event["side_a"]
    assert_equal "Rebels", event["side_b"]
    assert_in_delta 15.0, event["lat"], 0.01
  end

  test "bounds filtering works" do
    get "/api/conflict_events", params: { lamin: 14.0, lamax: 16.0, lomin: 44.0, lomax: 46.0 }
    data = JSON.parse(response.body)
    assert data.any?

    get "/api/conflict_events", params: { lamin: 0.0, lamax: 5.0, lomin: 0.0, lomax: 5.0 }
    data = JSON.parse(response.body)
    assert_empty data
  end
end
