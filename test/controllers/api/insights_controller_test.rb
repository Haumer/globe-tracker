require "test_helper"

class Api::InsightsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(email: "insights@example.com", password: "password123")
    sign_in @user
  end

  test "GET /api/insights returns insights array" do
    LayerSnapshot.create!(
      snapshot_type: "insights",
      scope_key: "global",
      payload: { insights: [{ title: "Signal", severity: "medium" }] },
      status: "ready",
      fetched_at: Time.current,
      expires_at: 5.minutes.from_now,
    )

    get "/api/insights"
    assert_response :success

    data = JSON.parse(response.body)
    assert data.key?("insights")
    assert_kind_of Array, data["insights"]
    assert_equal "ready", data["snapshot_status"]
  end

  test "unauthenticated request still returns insights for the public home page" do
    sign_out @user

    LayerSnapshot.create!(
      snapshot_type: "insights",
      scope_key: "global",
      payload: { insights: [{ title: "Public signal", severity: "low" }] },
      status: "ready",
      fetched_at: Time.current,
      expires_at: 5.minutes.from_now,
    )

    get "/api/insights"
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal "ready", data["snapshot_status"]
    assert_equal 1, data["insights"].length
  end
end
