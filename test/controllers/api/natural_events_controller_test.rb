require "test_helper"

class Api::NaturalEventsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @event = NaturalEvent.create!(
      external_id: "ne-ctrl-001",
      title: "Tropical Storm Test",
      category_id: "severeStorms",
      category_title: "Severe Storms",
      latitude: 25.0,
      longitude: -80.0,
      event_date: 6.hours.ago,
      fetched_at: Time.current
    )
  end

  test "GET /api/natural_events returns JSON array" do
    get "/api/natural_events"
    assert_response :success

    data = JSON.parse(response.body)
    assert_kind_of Array, data
  end

  test "response contains expected fields" do
    get "/api/natural_events"
    data = JSON.parse(response.body)
    event = data.find { |e| e["id"] == "ne-ctrl-001" }

    assert_not_nil event
    assert_equal "Tropical Storm Test", event["title"]
    assert_equal "severeStorms", event["categoryId"]
  end
end
