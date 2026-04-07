require "test_helper"

class HealthControllerTest < ActionDispatch::IntegrationTest
  setup do
    ServiceRuntimeState.where(service_name: "poller").delete_all
    PollingStat.delete_all
    @original_disabled_layers = LayerAvailability.disabled_layers
  end

  teardown do
    LayerAvailability.disabled_layers = @original_disabled_layers
  end

  test "health reports down when poller heartbeat is stale" do
    get "/health"

    assert_response :service_unavailable
    payload = JSON.parse(response.body)
    assert_equal "down", payload["status"]
    assert_equal "stale", payload["poller"]
  end

  test "health reports healthy when poller heartbeat is fresh and sources are fresh" do
    LayerAvailability.disabled_layers = []
    PollerRuntimeState.heartbeat!(
      reported_state: "running",
      metadata: { "started_at" => Time.current.iso8601, "poll_count" => 3, "ais_mode" => "stream" }
    )
    seed_successful_sources(include_hafas: true, include_ais: true)

    get "/health"

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal "healthy", payload["status"]
    assert_equal "running", payload["poller"]
  end

  test "health keeps slower sources healthy within their real cadence" do
    PollerRuntimeState.heartbeat!(
      reported_state: "running",
      metadata: { "started_at" => Time.current.iso8601, "poll_count" => 3, "ais_mode" => "disabled" }
    )
    seed_successful_sources(celestrak_at: 5.hours.ago)

    get "/health"

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal "healthy", payload["status"]
    assert_equal "ok", payload.dig("sources", "celestrak", "status")
  end

  test "health marks intentionally disabled feeds as disabled instead of stale" do
    PollerRuntimeState.heartbeat!(
      reported_state: "running",
      metadata: { "started_at" => Time.current.iso8601, "poll_count" => 3, "ais_mode" => "disabled" }
    )
    seed_successful_sources

    get "/health"

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal "healthy", payload["status"]
    assert_equal "disabled", payload.dig("sources", "hafas", "status")
    assert_equal "disabled", payload.dig("sources", "ais", "status")
  end

  private

  def seed_successful_sources(celestrak_at: 10.seconds.ago, include_hafas: false, include_ais: false)
    sources = {
      "opensky" => 10.seconds.ago,
      "adsb-europe" => 10.seconds.ago,
      "usgs" => 10.seconds.ago,
      "gdelt" => 10.seconds.ago,
      "multi-news" => 10.seconds.ago,
      "rss" => 10.seconds.ago,
      "celestrak" => celestrak_at,
      "firms" => 10.seconds.ago,
    }
    sources["hafas"] = 10.seconds.ago if include_hafas
    sources["ais"] = 10.seconds.ago if include_ais

    sources.each do |source, created_at|
      PollingStatRecorder.record(
        source: source,
        poll_type: poll_type_for(source),
        status: "success",
        created_at: created_at
      )
    end
  end

  def poll_type_for(source)
    case source
    when "opensky", /\Aadsb-/
      "flights"
    when "hafas"
      "trains"
    when "usgs"
      "earthquakes"
    when "gdelt", "multi-news", "rss"
      "news"
    when "celestrak"
      "satellites"
    when "firms"
      "fires"
    when "ais"
      "ships"
    else
      "health"
    end
  end
end
