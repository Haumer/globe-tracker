class GlobalPollerService
  POLL_INTERVAL = 30 # seconds

  class << self
    def start
      return if @running
      @running = true
      @thread = Thread.new { poll_loop }
      @thread.abort_on_exception = true
      Rails.logger.info("GlobalPollerService: started")
    end

    def stop
      @running = false
      @thread&.join(5)
      Rails.logger.info("GlobalPollerService: stopped")
    end

    def running?
      @running && @thread&.alive?
    end

    def status
      {
        running: running?,
        started_at: @started_at,
        last_poll_at: @last_poll_at,
        poll_count: @poll_count || 0,
      }
    end

    private

    def poll_loop
      @started_at = Time.current
      @poll_count = 0

      while @running
        begin
          poll_all
          @last_poll_at = Time.current
          @poll_count += 1
        rescue => e
          Rails.logger.error("GlobalPollerService: #{e.message}")
        end

        sleep POLL_INTERVAL
      end
    end

    def poll_all
      # Flights - OpenSky (global, no bounds)
      poll_source("opensky", "flight") do
        OpenskyService.fetch_flights(bounds: {})
      end

      # Flights - ADSB (global)
      poll_source("adsb", "flight") do
        AdsbService.fetch_flights(bounds: {})
      end

      # Ships - AIS (WebSocket stream, just ensure it's running)
      poll_source("ais", "ship") do
        unless AisStreamService.running?
          AisStreamService.start
        end
        Ship.where("updated_at > ?", 2.minutes.ago)
      end
    end

    def poll_source(source, poll_type)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = yield
      duration = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round

      count = result.respond_to?(:count) ? result.count : 0

      PollingStat.create!(
        source: source,
        poll_type: poll_type,
        records_fetched: count,
        records_stored: count,
        duration_ms: duration,
        status: "success"
      )
    rescue => e
      duration = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round rescue 0
      PollingStat.create!(
        source: source,
        poll_type: poll_type,
        records_fetched: 0,
        records_stored: 0,
        duration_ms: duration,
        status: "error",
        error_message: e.message.truncate(500)
      )
    end
  end
end
