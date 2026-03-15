require "test_helper"

class BackgroundRefreshSchedulerTest < ActiveSupport::TestCase
  setup do
    BackgroundRefreshScheduler.reset!
  end

  test "claim acquires lock and second claim is rejected" do
    first = BackgroundRefreshScheduler.send(:claim, "test_lock", 60)
    assert first

    second = BackgroundRefreshScheduler.send(:claim, "test_lock", 60)
    assert_not second
  end

  test "claim allows re-acquisition after TTL expires" do
    BackgroundRefreshScheduler.send(:claim, "test_lock_ttl", 0.001)
    sleep 0.01
    result = BackgroundRefreshScheduler.send(:claim, "test_lock_ttl", 60)
    assert result
  end

  test "reset! clears all local locks" do
    BackgroundRefreshScheduler.send(:claim, "lock_a", 60)
    BackgroundRefreshScheduler.reset!
    result = BackgroundRefreshScheduler.send(:claim, "lock_a", 60)
    assert result
  end
end
