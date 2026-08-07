class PollerRuntime
  LOOP_INTERVAL = GlobalPollerService::LOOP_INTERVAL

  # A crashed poller is invisible: when embedded in Sidekiq it is just a thread,
  # and a dead thread stops no jobs and logs nothing. Supervise it instead.
  MAX_RESTARTS = 10
  RESTART_BACKOFF = 5.seconds

  class << self
    # Entry point for the embedded (Sidekiq thread) runner. Restarts the loop on
    # unexpected errors so a single failure cannot silently end ingest.
    def run_supervised
      restarts = 0

      begin
        run
      rescue StandardError => e
        restarts += 1
        log_crash(e, restarts)

        if restarts <= MAX_RESTARTS && !stop_requested_externally?
          sleep(RESTART_BACKOFF * [restarts, 6].min)
          retry
        end

        Rails.logger.error("[poller] giving up after #{restarts} restart(s); ingest is stopped")
      end
    end

    # Ask *this* process's loop to wind down. Deliberately not the same thing as
    # PollerRuntimeState.request_stop!, which records operator intent for every
    # process. Shutting one container down must not tell the next one to stay off.
    def request_local_stop!
      @stop_requested = true
    end

    def run
      @stop_requested = false
      # Only trap when we own the process. Embedded in Sidekiq, these traps would
      # replace Sidekiq's own INT/TERM handlers and break its graceful shutdown;
      # the initializer's on(:shutdown) hook already requests a stop there.
      trap_signals unless embedded?
      PollerRuntimeState.ensure_running!

      loop do
        break if @stop_requested

        desired_state = PollerRuntimeState.desired_state

        case desired_state
        when "paused"
          stop_ais_if_running
          PollerRuntimeState.heartbeat!(
            reported_state: "paused",
            metadata: runtime_metadata
          )
        when "stopped"
          break
        else
          start_ais_if_enabled
          GlobalPollerService.tick!(now: Time.current)
        end

        interruptible_sleep(LOOP_INTERVAL)
      end
    rescue Interrupt, SignalException
      # fall through to shutdown
    ensure
      stop_ais_if_running
      PollerRuntimeState.heartbeat!(
        reported_state: "stopped",
        metadata: runtime_metadata.merge("stopped_at" => Time.current.iso8601)
      ) rescue nil
    end

    private

    def embedded?
      ENV["EMBED_POLLER_IN_WORKER"] == "1"
    end

    def stop_requested_externally?
      PollerRuntimeState.desired_state == "stopped"
    rescue StandardError
      false
    end

    def log_crash(error, restarts)
      Rails.logger.error("[poller] crashed (#{restarts}/#{MAX_RESTARTS}): #{error.class}: #{error.message}")
      Rails.logger.error(Array(error.backtrace).first(20).join("\n"))
    end

    # sleep(LOOP_INTERVAL) would delay shutdown by up to a full interval after a
    # signal sets the flag, so wake up often enough to notice it.
    def interruptible_sleep(seconds)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds.to_f

      loop do
        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        break if remaining <= 0 || @stop_requested

        sleep([remaining, 1].min)
      end
    end

    def runtime_metadata
      status = PollerRuntimeState.status

      {
        "started_at" => status[:started_at]&.iso8601 || Time.current.iso8601,
        "last_poll_at" => status[:last_poll_at]&.iso8601,
        "last_tick_at" => status[:last_tick_at]&.iso8601,
        "poll_count" => status[:poll_count].to_i,
        "ais_mode" => ais_mode,
        "ais_running" => AisStreamService.running?,
        "scheduler" => runtime_owner,
      }.compact
    end

    def ais_mode
      ENV["AISSTREAM_API_KEY"].present? ? "stream" : "disabled"
    end

    def start_ais_if_enabled
      return unless ENV["AISSTREAM_API_KEY"].present?

      AisStreamService.start unless AisStreamService.running?
    end

    def stop_ais_if_running
      AisStreamService.stop if AisStreamService.running?
    end

    # Trap handlers run in trap context, where Ruby forbids taking a mutex. The
    # old handler called PollerRuntimeState.request_stop!, which writes to the DB
    # and so grabs a connection-pool mutex -- raising
    # "ThreadError: can't be called from trap context" and killing the loop.
    # Set a flag only; the loop does the DB work in normal context.
    def trap_signals
      %w[INT TERM].each do |signal|
        Signal.trap(signal) { @stop_requested = true }
      end
    end

    def runtime_owner
      dyno = ENV["DYNO"].to_s
      return "worker" if dyno.start_with?("worker")

      "poller"
    end
  end
end
