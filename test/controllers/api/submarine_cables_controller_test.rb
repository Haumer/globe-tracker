require "test_helper"

class Api::SubmarineCablesControllerTest < ActionDispatch::IntegrationTest
  test "GET /api/submarine_cables returns cable data" do
    SubmarineCable.create!(
      cable_id: "cable-001",
      name: "TAT-14",
      color: "#0000ff",
      coordinates: [[-50.0, 40.0], [-10.0, 50.0]]
    )

    get "/api/submarine_cables"
    assert_response :success

    data = JSON.parse(response.body)
    assert_kind_of Array, data["cables"]
    assert_equal 1, data["cables"].size
    assert_equal "TAT-14", data["cables"].first["name"]
  end

  test "GET /api/submarine_cables with empty DB returns empty cables" do
    get "/api/submarine_cables"
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal [], data["cables"]
  end
end
