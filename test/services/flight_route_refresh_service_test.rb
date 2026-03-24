require "test_helper"

class FlightRouteRefreshServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @original_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
    clear_performed_jobs
    Rails.cache.clear
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
    ActiveJob::Base.queue_adapter = @original_queue_adapter
    Rails.cache.clear
  end

  test "enqueue_if_needed creates pending route record and enqueues job" do
    assert_enqueued_with(job: RefreshFlightRouteJob, args: ["DLH123", "abc123"]) do
      queued = FlightRouteRefreshService.enqueue_if_needed(callsign: " dlh123 ", flight_icao24: "abc123")
      assert_equal true, queued
    end

    route = FlightRoute.find_by!(callsign: "DLH123")
    assert_equal "pending", route.status
    assert_equal "abc123", route.flight_icao24
  end

  test "enqueue_if_needed skips fresh routes" do
    FlightRoute.create!(
      callsign: "DLH123",
      flight_icao24: "abc123",
      route: ["LOWW", "EDDF"],
      raw_payload: { "route" => ["LOWW", "EDDF"] },
      status: "fetched",
      fetched_at: Time.current,
      expires_at: 20.minutes.from_now,
    )

    assert_no_enqueued_jobs do
      queued = FlightRouteRefreshService.enqueue_if_needed(callsign: "DLH123", flight_icao24: "abc123")
      assert_equal false, queued
    end
  end

  test "refresh persists successful route fetch" do
    with_stubbed_fetch_route(
      callsign: "DLH123",
      route: ["LOWW", "EDDF"],
      operator_iata: "LH",
      flight_number: "123",
      raw_payload: { "callsign" => "DLH123", "route" => ["LOWW", "EDDF"] },
    ) do
      route = FlightRouteRefreshService.refresh(callsign: "DLH123", flight_icao24: "abc123", force: true)

      assert_equal "fetched", route.status
      assert_equal ["LOWW", "EDDF"], route.route
      assert_equal "LH", route.operator_iata
      assert_equal "123", route.flight_number
      assert_equal({ "callsign" => "DLH123", "route" => ["LOWW", "EDDF"] }, route.raw_payload)
      assert route.expires_at > Time.current
    end
  end

  test "refresh persists failed route fetch" do
    with_stubbed_fetch_route(error: "Route not found") do
      route = FlightRouteRefreshService.refresh(callsign: "DLH123", flight_icao24: "abc123", force: true)

      assert_equal "failed", route.status
      assert_equal "Route not found", route.error_code
      assert_equal [], route.route
      assert route.expires_at > Time.current
    end
  end

  def with_stubbed_fetch_route(result)
    original = OpenskyService.method(:fetch_route)
    OpenskyService.define_singleton_method(:fetch_route) { |_callsign| result }
    yield
  ensure
    OpenskyService.define_singleton_method(:fetch_route, original)
  end
end
