class PollerRuntime
  HEARTBEAT_INTERVAL = 15

  class << self
    def run
      trap_signals
      PollerRuntimeState.ensure_running!
      GlobalPollerService.start unless GlobalPollerService.running?

      loop do
        desired_state = PollerRuntimeState.desired_state

        case desired_state
        when "paused"
          GlobalPollerService.pause unless GlobalPollerService.paused?
          AisStreamService.stop if AisStreamService.running?
        when "stopped"
          break
        else
          GlobalPollerService.resume if GlobalPollerService.paused?
          GlobalPollerService.start unless GlobalPollerService.running?
          AisStreamService.start unless AisStreamService.running?
        end

        PollerRuntimeState.heartbeat!(
          reported_state: desired_state == "paused" ? "paused" : "running",
          metadata: heartbeat_metadata
        )

        sleep HEARTBEAT_INTERVAL
      end
    rescue Interrupt, SignalException
      # fall through to shutdown
    ensure
      PollerRuntimeState.heartbeat!(
        reported_state: "stopping",
        metadata: heartbeat_metadata
      ) rescue nil
      AisStreamService.stop if AisStreamService.running?
      GlobalPollerService.stop if GlobalPollerService.running?
      PollerRuntimeState.heartbeat!(
        reported_state: "stopped",
        metadata: heartbeat_metadata.merge("stopped_at" => Time.current.iso8601)
      ) rescue nil
    end

    private

    def heartbeat_metadata
      poller_status = GlobalPollerService.status
      {
        "started_at" => poller_status[:started_at]&.iso8601,
        "last_poll_at" => poller_status[:last_poll_at]&.iso8601,
        "poll_count" => poller_status[:poll_count].to_i,
        "ais_running" => AisStreamService.running?,
      }
    end

    def trap_signals
      %w[INT TERM].each do |signal|
        Signal.trap(signal) do
          PollerRuntimeState.request_stop!
        end
      end
    end
  end
end
