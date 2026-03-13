require "test_helper"

class Api::WeatherAlertsControllerTest < ActionDispatch::IntegrationTest
  test "returns weather alerts" do
    get "/api/weather_alerts"
    assert_response :success

    body = JSON.parse(response.body)
    assert body.key?("alerts")
    assert body.key?("count")
    assert body.key?("fetched_at")
    assert_kind_of Array, body["alerts"]
  end

  test "alerts have required fields when present" do
    get "/api/weather_alerts"
    body = JSON.parse(response.body)

    if body["alerts"].any?
      alert = body["alerts"].first
      assert alert.key?("event")
      assert alert.key?("severity")
      assert alert.key?("lat")
      assert alert.key?("lng")
    end
  end
end
