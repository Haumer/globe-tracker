class PollerRuntimeState
  SERVICE_NAME = "poller".freeze
  HEARTBEAT_TTL = 90.seconds

  class << self
    def status
      state = current_state
      metadata = state.metadata || {}
      heartbeat_fresh = state.reported_at.present? && state.reported_at >= HEARTBEAT_TTL.ago
      runtime_running = heartbeat_fresh && state.reported_state == "running"
      runtime_paused = heartbeat_fresh && state.reported_state == "paused"
      runtime_stopped = state.desired_state == "stopped" ||
        (heartbeat_fresh && state.reported_state == "stopped")

      {
        desired_state: state.desired_state,
        reported_state: state.reported_state,
        running: runtime_running,
        paused: runtime_paused,
        stopped: runtime_stopped,
        stale: !runtime_stopped && !heartbeat_fresh,
        externally_managed: true,
        scheduler: metadata["scheduler"] || "poller",
        started_at: parse_time(metadata["started_at"]),
        last_poll_at: parse_time(metadata["last_poll_at"]),
        last_tick_at: parse_time(metadata["last_tick_at"]) || state.reported_at,
        last_heartbeat_at: state.reported_at,
        poll_count: metadata["poll_count"].to_i,
        ais_mode: metadata["ais_mode"] || "disabled",
        ais_running: metadata["ais_running"] == true,
        last_error: metadata["last_error"],
      }
    end

    def ensure_running!
      state = current_state
      state.update!(desired_state: "running")
      state
    end

    def request_pause!
      current_state.update!(desired_state: "paused")
    end

    def request_resume!
      current_state.update!(desired_state: "running")
    end

    def request_stop!
      current_state.update!(desired_state: "stopped")
    end

    def increment_poll_count!(now: Time.current)
      state = current_state
      state.with_lock do
        metadata = (state.metadata || {}).dup
        metadata["poll_count"] = metadata["poll_count"].to_i + 1
        metadata["started_at"] ||= now.iso8601
        state.update!(metadata: metadata)
        metadata["poll_count"]
      end
    end

    def desired_state
      current_state.desired_state
    end

    def heartbeat!(reported_state:, metadata: {})
      state = current_state
      state.update!(
        reported_state: reported_state,
        reported_at: Time.current,
        metadata: (state.metadata || {}).merge(metadata)
      )
      state
    end

    private

    def current_state
      ServiceRuntimeState.find_or_create_by!(service_name: SERVICE_NAME) do |state|
        state.desired_state = "running"
        state.reported_state = "stopped"
        state.reported_at = nil
        state.metadata = {}
      end
    end

    def parse_time(value)
      return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
      return nil if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
