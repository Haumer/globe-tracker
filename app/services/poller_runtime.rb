class PollerRuntime
  LOOP_INTERVAL = 15.seconds

  class << self
    def run
      trap_signals
      PollerRuntimeState.ensure_running!

      loop do
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

        sleep LOOP_INTERVAL
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

    def runtime_metadata
      status = PollerRuntimeState.status

      {
        "started_at" => status[:started_at]&.iso8601 || Time.current.iso8601,
        "last_poll_at" => status[:last_poll_at]&.iso8601,
        "last_tick_at" => status[:last_tick_at]&.iso8601,
        "poll_count" => status[:poll_count].to_i,
        "ais_mode" => ais_mode,
        "ais_running" => AisStreamService.running?,
        "scheduler" => "poller",
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

    def trap_signals
      %w[INT TERM].each do |signal|
        Signal.trap(signal) do
          PollerRuntimeState.request_stop!
        end
      end
    end
  end
end
