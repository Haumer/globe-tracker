require "test_helper"

# Drives the pure decision method; threads, sleeps, /proc and Process.exit!
# never run in tests.
class WorkerWatchdogTest < ActiveSupport::TestCase
  setup do
    @clock_now = 0.0
    @watchdog = WorkerWatchdog.new(clock: -> { @clock_now })
  end

  test "healthy worker produces no exit reason" do
    pass_boot_grace

    assert_nil @watchdog.assess(rss_mb: 800, poller: :ok)
  end

  test "RSS over the cap exits immediately, even inside the boot grace" do
    reason = @watchdog.assess(rss_mb: WorkerWatchdog.max_rss_mb + 1, poller: :ok)

    assert_match(/RSS/, reason)
  end

  test "unreadable RSS is not an exit reason" do
    pass_boot_grace

    assert_nil @watchdog.assess(rss_mb: nil, poller: :ok)
  end

  test "stale heartbeat inside the boot grace is ignored" do
    WorkerWatchdog::STALE_EXITS_AFTER.times do
      assert_nil @watchdog.assess(rss_mb: 800, poller: :stale)
    end
  end

  test "a stale streak past the threshold exits; a healthy check resets it" do
    pass_boot_grace

    (WorkerWatchdog::STALE_EXITS_AFTER - 1).times do
      assert_nil @watchdog.assess(rss_mb: 800, poller: :stale)
    end
    assert_nil @watchdog.assess(rss_mb: 800, poller: :ok)

    (WorkerWatchdog::STALE_EXITS_AFTER - 1).times do
      assert_nil @watchdog.assess(rss_mb: 800, poller: :stale)
    end
    reason = @watchdog.assess(rss_mb: 800, poller: :stale)

    assert_match(/heartbeat stale/, reason)
  end

  test "status read failures exit only after their own longer streak" do
    pass_boot_grace

    (WorkerWatchdog::STATUS_FAILURE_EXITS_AFTER - 1).times do
      assert_nil @watchdog.assess(rss_mb: 800, poller: :error)
    end
    reason = @watchdog.assess(rss_mb: 800, poller: :error)

    assert_match(/unreadable/, reason)
  end

  test "watchdog can be disabled by env" do
    original = ENV["WORKER_WATCHDOG"]
    ENV["WORKER_WATCHDOG"] = "0"

    assert_not WorkerWatchdog.enabled?
  ensure
    original.nil? ? ENV.delete("WORKER_WATCHDOG") : ENV["WORKER_WATCHDOG"] = original
  end

  private

  def pass_boot_grace
    @clock_now += WorkerWatchdog::BOOT_GRACE.to_f + 1
  end
end
