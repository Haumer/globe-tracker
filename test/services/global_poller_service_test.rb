require "test_helper"

class GlobalPollerServiceTest < ActiveSupport::TestCase
  setup do
    # Ensure clean state — stop if running from a previous test
    GlobalPollerService.instance_variable_set(:@running, false)
    GlobalPollerService.instance_variable_set(:@paused, false)
    GlobalPollerService.instance_variable_set(:@thread, nil)
  end

  test "status returns a hash with expected keys" do
    status = GlobalPollerService.status
    assert_kind_of Hash, status
    assert status.key?(:running)
    assert status.key?(:paused)
    assert status.key?(:poll_count)
  end

  test "initially not running and not paused" do
    assert_not GlobalPollerService.running?
    assert_not GlobalPollerService.paused?
  end

  test "pause sets paused state" do
    GlobalPollerService.pause
    assert GlobalPollerService.paused?
    GlobalPollerService.resume
    assert_not GlobalPollerService.paused?
  end

  test "stop resets all state" do
    GlobalPollerService.instance_variable_set(:@running, true)
    GlobalPollerService.instance_variable_set(:@paused, true)
    GlobalPollerService.stop
    assert_not GlobalPollerService.running?
    assert_not GlobalPollerService.paused?
  end

  test "constants are defined" do
    assert_equal 10, GlobalPollerService::FLIGHT_POLL_INTERVAL
    assert_equal 60, GlobalPollerService::FULL_POLL_INTERVAL
  end
end
