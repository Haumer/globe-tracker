require "test_helper"

class HealthControllerTest < ActionDispatch::IntegrationTest
  setup do
    ServiceRuntimeState.where(service_name: "poller").delete_all
  end

  test "health reports down when poller heartbeat is stale" do
    get "/health"

    assert_response :service_unavailable
    payload = JSON.parse(response.body)
    assert_equal "down", payload["status"]
    assert_equal "stale", payload["poller"]
  end

  test "health reports healthy when poller heartbeat is fresh and sources are fresh" do
    PollerRuntimeState.heartbeat!(
      reported_state: "running",
      metadata: { "started_at" => Time.current.iso8601, "poll_count" => 3 }
    )
    PollingStatRecorder.record(source: "opensky", poll_type: "flights", status: "success", created_at: 10.seconds.ago)
    PollingStatRecorder.record(source: "adsb-europe", poll_type: "flights", status: "success", created_at: 10.seconds.ago)
    PollingStatRecorder.record(source: "hafas", poll_type: "trains", status: "success", created_at: 10.seconds.ago)
    PollingStatRecorder.record(source: "usgs", poll_type: "earthquakes", status: "success", created_at: 10.seconds.ago)
    PollingStatRecorder.record(source: "gdelt", poll_type: "news", status: "success", created_at: 10.seconds.ago)
    PollingStatRecorder.record(source: "multi-news", poll_type: "news", status: "success", created_at: 10.seconds.ago)
    PollingStatRecorder.record(source: "rss", poll_type: "news", status: "success", created_at: 10.seconds.ago)
    PollingStatRecorder.record(source: "celestrak", poll_type: "satellites", status: "success", created_at: 10.seconds.ago)
    PollingStatRecorder.record(source: "firms", poll_type: "fires", status: "success", created_at: 10.seconds.ago)
    PollingStatRecorder.record(source: "ais", poll_type: "ships", status: "success", created_at: 10.seconds.ago)

    get "/health"

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal "healthy", payload["status"]
    assert_equal "running", payload["poller"]
  end
end
