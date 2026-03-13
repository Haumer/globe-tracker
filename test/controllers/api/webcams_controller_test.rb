require "test_helper"

class Api::WebcamsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    Camera.create!(
      webcam_id: "windy-123", source: "windy", title: "Vienna Cam",
      latitude: 48.2, longitude: 16.3, status: "active",
      is_live: true, camera_type: "live",
      fetched_at: Time.current, expires_at: 30.days.from_now,
    )
    Camera.create!(
      webcam_id: "yt-abc", source: "youtube", title: "YouTube Live",
      latitude: 48.21, longitude: 16.31, status: "active",
      is_live: true, camera_type: "live",
      fetched_at: Time.current, expires_at: 3.hours.from_now,
    )
  end

  test "returns cameras within bounding box" do
    get "/api/webcams", params: { north: 49, south: 47, east: 17, west: 15 }
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal 2, body["webcams"].size
    assert_equal false, body["stale"]
  end

  test "returns empty array when no cameras in bbox" do
    get "/api/webcams", params: { north: 10, south: 9, east: 10, west: 9 }
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal 0, body["webcams"].size
    assert_equal true, body["stale"]
  end

  test "requires bounding box params" do
    get "/api/webcams"
    assert_response :bad_request
  end

  test "respects limit parameter" do
    get "/api/webcams", params: { north: 49, south: 47, east: 17, west: 15, limit: 1 }
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal 1, body["webcams"].size
  end

  test "enqueues refresh job when cameras are stale" do
    Camera.update_all(expires_at: 1.hour.ago)

    assert_enqueued_with(job: RefreshCamerasJob) do
      get "/api/webcams", params: { north: 49, south: 47, east: 17, west: 15 }
    end

    body = JSON.parse(response.body)
    assert_equal true, body["stale"]
  end

  test "serializes camera with expected fields" do
    get "/api/webcams", params: { north: 49, south: 47, east: 17, west: 15, limit: 1 }
    cam = JSON.parse(response.body)["webcams"].first

    assert cam.key?("webcamId")
    assert cam.key?("title")
    assert cam.key?("source")
    assert cam.key?("live")
    assert cam.key?("location")
    assert cam["location"].key?("latitude")
    assert cam["location"].key?("longitude")
    assert cam.key?("images")
    assert cam.key?("stale")
  end

  test "sorts youtube/nycdot before windy" do
    get "/api/webcams", params: { north: 49, south: 47, east: 17, west: 15 }
    webcams = JSON.parse(response.body)["webcams"]

    assert_equal "youtube", webcams.first["source"]
  end
end
