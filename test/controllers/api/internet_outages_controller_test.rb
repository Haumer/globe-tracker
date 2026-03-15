require "test_helper"

class Api::InternetOutagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @outage = InternetOutage.create!(
      external_id: "outage-ctrl-001",
      entity_type: "country",
      entity_code: "AT",
      entity_name: "Austria",
      level: "major",
      score: 75.0,
      started_at: 2.hours.ago
    )
  end

  test "GET /api/internet_outages returns JSON with summary and events" do
    get "/api/internet_outages"
    assert_response :success

    data = JSON.parse(response.body)
    assert data.key?("summary")
    assert data.key?("events")
    assert_kind_of Array, data["events"]
  end

  test "events contain expected fields" do
    get "/api/internet_outages"
    data = JSON.parse(response.body)
    event = data["events"].find { |e| e["id"] == "outage-ctrl-001" }

    assert_not_nil event
    assert_equal "AT", event["code"]
    assert_equal "Austria", event["name"]
  end
end
