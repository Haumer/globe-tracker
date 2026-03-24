require "test_helper"

class Api::ChokepointsControllerTest < ActionDispatch::IntegrationTest
  test "GET /api/chokepoints returns persisted chokepoints" do
    LayerSnapshot.create!(
      snapshot_type: "chokepoints",
      scope_key: "global",
      payload: {
        chokepoints: [
          { id: "hormuz", name: "Strait of Hormuz", status: "monitoring" },
        ],
      },
      status: "ready",
      fetched_at: Time.current,
      expires_at: 15.minutes.from_now,
    )

    get "/api/chokepoints"
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal 1, data["count"]
    assert_equal "ready", data["snapshot_status"]
    assert_equal "Strait of Hormuz", data["chokepoints"].first["name"]
  end
end
