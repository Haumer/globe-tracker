require "test_helper"

class PollerRuntimeStateTest < ActiveSupport::TestCase
  setup do
    ServiceRuntimeState.where(service_name: "poller").delete_all
  end

  test "status is stale without a heartbeat" do
    status = PollerRuntimeState.status

    assert_equal "running", status[:desired_state]
    assert status[:stale]
    assert_not status[:running]
    assert_not status[:paused]
  end

  test "heartbeat marks the runtime as running" do
    PollerRuntimeState.heartbeat!(
      reported_state: "running",
      metadata: {
        "started_at" => Time.current.iso8601,
        "last_poll_at" => 10.seconds.ago.iso8601,
        "poll_count" => 12,
        "ais_running" => true,
      }
    )

    status = PollerRuntimeState.status
    assert status[:running]
    assert_not status[:stale]
    assert_equal 12, status[:poll_count]
    assert_equal true, status[:ais_running]
  end

  test "pause and resume change desired state" do
    PollerRuntimeState.request_pause!
    assert_equal "paused", PollerRuntimeState.desired_state

    PollerRuntimeState.request_resume!
    assert_equal "running", PollerRuntimeState.desired_state
  end
end
