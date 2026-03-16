class GlobalPollerService
  FLIGHT_POLL_INTERVAL = 10 # seconds
  FULL_POLL_INTERVAL   = 60 # seconds — enqueue Sidekiq jobs for secondary sources

  class << self
    def start
      return if @running
      @running = true
      @thread = Thread.new { poll_loop }
      @thread.name = "global-poller"
      Rails.logger.info("GlobalPollerService: started")
    end

    def pause
      @paused = true
      Rails.logger.info("GlobalPollerService: paused")
    end

    def resume
      @paused = false
      Rails.logger.info("GlobalPollerService: resumed")
    end

    def stop
      @running = false
      @paused = false
      unless @thread&.join(3)
        @thread&.kill
      end
      @thread = nil
      Rails.logger.info("GlobalPollerService: stopped")
    end

    def running?
      @running && @thread&.alive?
    end

    def paused?
      @paused == true
    end

    def status
      {
        running: running?,
        paused: paused?,
        started_at: @started_at,
        last_poll_at: @last_poll_at,
        poll_count: @poll_count || 0,
      }
    end

    private

    def poll_loop
      @started_at = Time.current
      @poll_count = 0

      @last_full_poll = 0
      @last_purge = 0

      while @running
        unless @paused
          begin
            poll_flights
            @poll_count += 1

            elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @last_full_poll
            if elapsed >= FULL_POLL_INTERVAL
              poll_secondary
              @last_full_poll = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            end

            @last_poll_at = Time.current

            # Hourly purge
            purge_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @last_purge
            if purge_elapsed >= 3600
              enqueue_once(PurgeStaleDataJob)
              @last_purge = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            end
          rescue => e
            Rails.logger.error("GlobalPollerService: #{e.message}")
          end
        end

        # Sleep in short intervals so the thread exits quickly on shutdown
        FLIGHT_POLL_INTERVAL.times { break unless @running; sleep 1 }
      end
    end

    # Regional centers for ADSB polling (250nm radius each covers ~460km)
    ADSB_REGIONS = [
      { name: "europe",    lat: 50, lon: 10 },
      { name: "na-east",   lat: 38, lon: -80 },
      { name: "na-west",   lat: 37, lon: -120 },
      { name: "mideast",   lat: 28, lon: 47 },
      { name: "east-asia", lat: 35, lon: 135 },
      { name: "se-asia",   lat: 5,  lon: 105 },
      { name: "oceania",   lat: -30, lon: 150 },
      { name: "south-am",  lat: -20, lon: -50 },
      { name: "africa",    lat: 5,  lon: 25 },
      { name: "india",     lat: 22, lon: 78 },
    ].freeze

    def poll_flights
      enqueue_once(PollOpenskyJob)
      enqueue_once(PollAdsbMilitaryJob)

      # Rotate through ADSB regions — one per cycle
      region = ADSB_REGIONS[@poll_count.to_i % ADSB_REGIONS.size]
      PollAdsbRegionJob.perform_later(region[:name], region[:lat], region[:lon])
    end

    def poll_secondary
      # AIS stream is a persistent WebSocket — just ensure it's running
      AisStreamService.start unless AisStreamService.running?

      # Enqueue all secondary refreshes as Sidekiq jobs.
      # Each job calls refresh_if_stale internally, so it no-ops if data is fresh.
      [
        RefreshEarthquakesJob,
        RefreshNewsJob,
        RefreshMultiNewsJob,
        RefreshRssNewsJob,
        RefreshFireHotspotsJob,
        RefreshNaturalEventsJob,
        RefreshConflictEventsJob,
        RefreshAcledJob,
        RefreshInternetOutagesJob,
        RefreshInternetTrafficJob,
        RefreshSatellitesJob,
        RefreshSubmarineCablesJob,
        RefreshGpsJammingJob,
        RefreshWeatherAlertsJob,
        RefreshNotamsJob,
        RefreshCommodityPricesJob,
        EnrichNewsJob,
      ].each { |job| enqueue_once(job) }
    end

    def enqueue_once(job_class)
      key = "poller:enqueued:#{job_class.name}"
      if Rails.cache.write(key, "1", expires_in: 60.seconds, unless_exist: true)
        job_class.perform_later
      end
    rescue => e
      job_class.perform_later
    end
  end
end
