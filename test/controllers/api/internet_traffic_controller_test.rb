require "test_helper"

class Api::InternetTrafficControllerTest < ActionDispatch::IntegrationTest
  test "GET /api/internet_traffic returns json with traffic data" do
    InternetTrafficSnapshot.create!(
      country_code: "US",
      country_name: "United States",
      traffic_pct: 25.0,
      attack_origin_pct: 10.0,
      attack_target_pct: 5.0,
      recorded_at: Time.current
    )

    get "/api/internet_traffic"
    assert_response :success

    data = JSON.parse(response.body)
    assert_kind_of Array, data["traffic"]
    assert data["traffic"].any? { |t| t["code"] == "US" }
    assert_equal "ready", response.headers["X-Source-Status"]
    assert_equal "0", response.headers["X-Source-Configured"]
  end

  test "GET /api/internet_traffic with empty DB returns empty traffic" do
    get "/api/internet_traffic"
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal [], data["traffic"]
    assert_equal "unconfigured", response.headers["X-Source-Status"]
    assert_equal "0", response.headers["X-Source-Configured"]
  end
end
