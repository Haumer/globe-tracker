require "test_helper"
require "webmock/minitest"

class Api::WeatherAlertsControllerTest < ActionDispatch::IntegrationTest
  setup do
    stub_request(:get, /api\.weather\.gov\/alerts/)
      .to_return(
        status: 200,
        body: {
          features: [
            {
              properties: {
                event: "Severe Thunderstorm Warning",
                severity: "Severe",
                headline: "Test alert",
                description: "Test description",
                areaDesc: "Test County",
                onset: Time.current.iso8601,
                expires: 2.hours.from_now.iso8601,
              },
              geometry: {
                type: "Polygon",
                coordinates: [[[-90.0, 35.0], [-89.0, 35.0], [-89.0, 36.0], [-90.0, 36.0], [-90.0, 35.0]]],
              },
            },
          ],
        }.to_json,
        headers: { "Content-Type" => "application/json" },
      )
  end

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
