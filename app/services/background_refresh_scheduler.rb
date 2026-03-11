class BackgroundRefreshScheduler
  @mutex = Mutex.new
  @local_locks = {}

  class << self
    def enqueue_once(job_class, *job_args, key:, ttl:)
      return false unless claim(key, ttl)

      job_class.perform_later(*job_args)
      true
    rescue StandardError => e
      Rails.logger.error("BackgroundRefreshScheduler enqueue error for #{key}: #{e.message}")
      false
    end

    def reset!
      @mutex.synchronize { @local_locks.clear }
    end

    private

    def claim(key, ttl)
      cache_key = "background-refresh:#{key}"

      if cache_store_available?
        Rails.cache.write(cache_key, true, expires_in: ttl, unless_exist: true)
      else
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        @mutex.synchronize do
          expires_at = @local_locks[cache_key]
          return false if expires_at && expires_at > now

          @local_locks[cache_key] = now + ttl.to_f
          true
        end
      end
    rescue StandardError => e
      Rails.logger.warn("BackgroundRefreshScheduler claim fallback for #{key}: #{e.message}")
      true
    end

    def cache_store_available?
      !Rails.cache.is_a?(ActiveSupport::Cache::NullStore)
    rescue StandardError
      false
    end
  end
end
