# The worker has died twice in ways the platform cannot see (2026-08-24 and
# 2026-08-27): once the poller thread ended while Sidekiq kept the process
# looking healthy, once the whole process went silent mid-backfill -- still
# "running" to Docker, no OOM kill, no logs for 14 hours. Container
# supervision watches the process; both failures live inside it. This thread
# watches the inside and, when it is sick, hard-exits so the platform's
# on-failure restart policy can do the one thing it is good at.
#
# Two triggers:
#
# - Poller heartbeat stale. PollerRuntimeState.status[:stale] is true only
#   when nobody deliberately paused or stopped ingest, so a streak of stale
#   checks means the thread is dead or the process is too sick to write a
#   heartbeat. Either way a restart fixes it.
# - RSS over a cap. The Aug 27 freeze looked like memory growth pushing the
#   host into swap until nothing ran -- at which point a watchdog thread is
#   as frozen as everything else. The exit has to happen on the way up,
#   while threads still get scheduled, so the cap is checked from boot with
#   no grace period.
#
# Exit is Process.exit!: no at_exit, no Sidekiq graceful shutdown. The states
# we exit on are exactly the states where graceful cannot be trusted; the
# periodic jobs this may cut short are idempotent refreshers.
class WorkerWatchdog
  CHECK_INTERVAL = 30.seconds
  # A fresh container's first heartbeat can lag boot (cold-start backfill,
  # migrations), and the previous container's last heartbeat may still be in
  # the row. Don't judge staleness until this process has had time to write
  # its own.
  BOOT_GRACE = 5.minutes
  # Heartbeat TTL is 90s; four stale reads 30s apart on top of that is ~3.5
  # minutes of certainty before pulling the trigger.
  STALE_EXITS_AFTER = 4
  # Status reads failing outright (connection pool starved, DB unreachable
  # from this process) are also a sick worker, but a single blip is not --
  # the 2026-08-26 Redis wobble lasted 3 seconds. Ten consecutive failures
  # is ~5 minutes of not even being able to ask.
  STATUS_FAILURE_EXITS_AFTER = 10
  # One RSS line every ~5 minutes leaves a memory curve in the container
  # logs, so the next freeze is a chart instead of a mystery.
  RSS_LOG_EVERY_TICKS = 10
  DEFAULT_MAX_RSS_MB = 4096

  class << self
    def enabled?
      ENV["WORKER_WATCHDOG"] != "0"
    end

    def max_rss_mb
      ENV.fetch("WORKER_MAX_RSS_MB", DEFAULT_MAX_RSS_MB).to_i
    end

    def run
      new.run
    end
  end

  def initialize(clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
    @clock = clock
    @booted_at = clock.call
    @stale_streak = 0
    @status_failure_streak = 0
    @ticks = 0
  end

  def run
    loop do
      sleep(CHECK_INTERVAL)
      tick
    end
  end

  def tick
    @ticks += 1
    rss = current_rss_mb

    if rss && (@ticks % RSS_LOG_EVERY_TICKS).zero?
      Rails.logger.info("[watchdog] worker RSS #{rss}MB (cap #{self.class.max_rss_mb}MB)")
    end

    reason = assess(rss_mb: rss, poller: read_poller_status)
    die!(reason) if reason
  rescue StandardError => e
    Rails.logger.warn("[watchdog] check failed: #{e.class}: #{e.message}")
  end

  # The whole decision, side-effect free, so tests can drive it without
  # threads, sleeps, or a real /proc.
  def assess(rss_mb:, poller:)
    if rss_mb && rss_mb > self.class.max_rss_mb
      return "RSS #{rss_mb}MB exceeds #{self.class.max_rss_mb}MB cap"
    end

    return nil if uptime_seconds < BOOT_GRACE

    case poller
    when :stale
      @stale_streak += 1
      @status_failure_streak = 0
      if @stale_streak >= STALE_EXITS_AFTER
        return "poller heartbeat stale across #{@stale_streak} consecutive checks"
      end
    when :error
      @status_failure_streak += 1
      if @status_failure_streak >= STATUS_FAILURE_EXITS_AFTER
        return "poller status unreadable for #{@status_failure_streak} consecutive checks"
      end
    else
      @stale_streak = 0
      @status_failure_streak = 0
    end

    nil
  end

  private

  def uptime_seconds
    @clock.call - @booted_at
  end

  def read_poller_status
    status = ActiveRecord::Base.connection_pool.with_connection { PollerRuntimeState.status }
    status[:stale] ? :stale : :ok
  rescue StandardError
    :error
  end

  def current_rss_mb
    if File.readable?("/proc/self/status")
      line = File.foreach("/proc/self/status").find { |l| l.start_with?("VmRSS:") }
      line && line.split[1].to_i / 1024
    else
      # Dev on macOS; ps reports KB.
      `ps -o rss= -p #{Process.pid}`.to_i / 1024
    end
  rescue StandardError
    nil
  end

  def die!(reason)
    message = "[watchdog] #{reason} -- exiting so the container supervisor restarts the worker"
    Rails.logger.error(message)
    # The logger can be buffered or wedged in exactly the states we exit on;
    # stderr goes straight to the container log.
    warn(message)
    Process.exit!(1)
  end
end
