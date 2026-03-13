class GlobalPollerService
  FLIGHT_POLL_INTERVAL = 10 # seconds
  FULL_POLL_INTERVAL   = 30 # seconds (for non-flight sources)

  class << self
    def start
      return if @running
      @running = true
      @thread = Thread.new { poll_loop }
      @thread.abort_on_exception = true
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
      @thread&.join(5)
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

      while @running
        unless @paused
          begin
            poll_flights
            @poll_count += 1

            # Run full poll (non-flight sources) every FULL_POLL_INTERVAL
            elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @last_full_poll
            if elapsed >= FULL_POLL_INTERVAL
              poll_secondary
              @last_full_poll = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            end

            @last_poll_at = Time.current
          rescue => e
            Rails.logger.error("GlobalPollerService: #{e.message}")
          ensure
            ActiveRecord::Base.connection_pool.release_connection
          end
        end

        sleep FLIGHT_POLL_INTERVAL
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
      # Flights - OpenSky (global, no bounds)
      poll_source("opensky", "flight") do
        OpenskyService.fetch_flights(bounds: {})
      end

      # Flights - ADSB (regional polls for global coverage)
      region = ADSB_REGIONS[@poll_count.to_i % ADSB_REGIONS.size]
      poll_source("adsb-#{region[:name]}", "flight") do
        bounds = {
          lamin: region[:lat] - 20, lamax: region[:lat] + 20,
          lomin: region[:lon] - 25, lomax: region[:lon] + 25,
        }
        AdsbService.fetch_flights(bounds: bounds)
      end

      # Military flights from ADSB (global endpoint)
      poll_source("adsb-mil", "flight") do
        AdsbService.fetch_military
      end
    end

    def poll_secondary
      # Ships - AIS (WebSocket stream, just ensure it's running)
      poll_source("ais", "ship") do
        unless AisStreamService.running?
          AisStreamService.start
        end
        Ship.where("updated_at > ?", 2.minutes.ago)
      end

      poll_source("usgs", "earthquake") do
        EarthquakeRefreshService.refresh_if_stale
      end

      poll_source("gdelt", "news") do
        NewsRefreshService.refresh_if_stale
      end

      poll_source("multi-news", "news") do
        MultiNewsService.refresh_if_stale
      end

      poll_source("rss-news", "news") do
        RssNewsService.refresh_if_stale
      end

      poll_source("firms", "fire") do
        FirmsRefreshService.refresh_if_stale
      end

      poll_source("eonet", "natural_event") do
        NaturalEventRefreshService.refresh_if_stale
      end

      poll_source("ucdp", "conflict_event") do
        ConflictEventService.refresh_if_stale
      end

      poll_source("acled", "conflict_event") do
        AcledService.refresh_if_stale
      end

      poll_source("cloudflare", "internet_outage") do
        InternetOutageRefreshService.refresh_if_stale
      end

      poll_source("cloudflare-traffic", "internet_traffic") do
        result = CloudflareRadarService.refresh_if_stale
        result.is_a?(Hash) ? (result[:traffic]&.size || 0) : 0
      end

      poll_source("celestrak", "satellite") do
        CelestrakService.refresh_if_stale
      end

      poll_source("submarine-cables", "submarine_cable") do
        SubmarineCableRefreshService.refresh_if_stale
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
