module CircuitBreaker
  FAILURE_THRESHOLD = 3
  OPEN_DURATION = 5.minutes

  CLOSED    = :closed
  OPEN      = :open
  HALF_OPEN = :half_open

  @mutex = Mutex.new
  # { key => { state:, failures:, opened_at: } }
  @circuits = {}

  class << self
    attr_reader :mutex, :circuits

    def state_for(key)
      mutex.synchronize do
        entry = circuits[key]
        return CLOSED unless entry

        if entry[:state] == OPEN && Time.current - entry[:opened_at] >= OPEN_DURATION
          transition(key, entry, HALF_OPEN)
        end

        entry[:state]
      end
    end

    def record_success(key)
      mutex.synchronize do
        entry = circuits[key]
        return unless entry

        if entry[:state] == HALF_OPEN || entry[:failures] > 0
          old_state = entry[:state]
          entry[:state] = CLOSED
          entry[:failures] = 0
          entry[:opened_at] = nil
          log_transition(key, old_state, CLOSED) unless old_state == CLOSED
        end
      end
    end

    def record_failure(key)
      mutex.synchronize do
        entry = circuits[key] ||= { state: CLOSED, failures: 0, opened_at: nil }
        entry[:failures] += 1

        if entry[:state] == HALF_OPEN
          transition(key, entry, OPEN)
        elsif entry[:state] == CLOSED && entry[:failures] >= FAILURE_THRESHOLD
          transition(key, entry, OPEN)
        end
      end
    end

    # Visible for testing — reset all circuit state.
    def reset!
      mutex.synchronize { circuits.clear }
    end

    private

    def transition(key, entry, new_state)
      old_state = entry[:state]
      entry[:state] = new_state
      entry[:opened_at] = Time.current if new_state == OPEN
      log_transition(key, old_state, new_state)
    end

    def log_transition(key, from, to)
      Rails.logger.warn("CircuitBreaker [#{key}]: #{from.upcase} → #{to.upcase}")
    end
  end

  # Build a circuit breaker key from a URI: "host/path"
  def circuit_key_for(uri)
    "#{uri.host}#{uri.path}".truncate(120)
  end
end
