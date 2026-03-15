class GlobalPollerService
  FLIGHT_POLL_INTERVAL = 10 # seconds
  FULL_POLL_INTERVAL   = 30 # seconds (for non-flight sources)

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

            # Run full poll (non-flight sources) every FULL_POLL_INTERVAL
            elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @last_full_poll
            if elapsed >= FULL_POLL_INTERVAL
              poll_secondary
              @last_full_poll = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            end

            @last_poll_at = Time.current

            # Hourly purge: keep DB within 10GB budget
            purge_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @last_purge
            if purge_elapsed >= 3600
              purge_stale_data
              @last_purge = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            end
          rescue => e
            Rails.logger.error("GlobalPollerService: #{e.message}")
          ensure
            ActiveRecord::Base.connection_pool.release_connection
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

    SECONDARY_SOURCES = [
      { name: "ais", type: "ship", fetcher: -> {
        AisStreamService.start unless AisStreamService.running?
        Ship.where("updated_at > ?", 2.minutes.ago)
      } },
      { name: "usgs",             type: "earthquake",       fetcher: -> { EarthquakeRefreshService.refresh_if_stale } },
      { name: "gdelt",            type: "news",             fetcher: -> { NewsRefreshService.refresh_if_stale } },
      { name: "multi-news",       type: "news",             fetcher: -> { MultiNewsService.refresh_if_stale } },
      { name: "rss-news",         type: "news",             fetcher: -> { RssNewsService.refresh_if_stale } },
      { name: "firms",            type: "fire",             fetcher: -> { FirmsRefreshService.refresh_if_stale } },
      { name: "eonet",            type: "natural_event",    fetcher: -> { NaturalEventRefreshService.refresh_if_stale } },
      { name: "ucdp",             type: "conflict_event",   fetcher: -> { ConflictEventService.refresh_if_stale } },
      { name: "acled",            type: "conflict_event",   fetcher: -> { AcledService.refresh_if_stale } },
      { name: "cloudflare",       type: "internet_outage",  fetcher: -> { InternetOutageRefreshService.refresh_if_stale } },
      { name: "cloudflare-traffic", type: "internet_traffic", fetcher: -> {
        result = CloudflareRadarService.refresh_if_stale
        result.is_a?(Hash) ? (result[:traffic]&.size || 0) : 0
      } },
      { name: "celestrak",        type: "satellite",        fetcher: -> { CelestrakService.refresh_if_stale } },
      { name: "submarine-cables", type: "submarine_cable",  fetcher: -> { SubmarineCableRefreshService.refresh_if_stale } },
      { name: "nws",              type: "weather_alert",   fetcher: -> { WeatherAlertRefreshService.refresh_if_stale } },
      { name: "notams",           type: "notam",           fetcher: -> { NotamRefreshService.refresh_if_stale } },
    ].freeze

    def poll_secondary
      SECONDARY_SOURCES.each { |s| poll_source(s[:name], s[:type], &s[:fetcher]) }
    end

    RETENTION = 7.days

    def purge_stale_data
      cutoff = RETENTION.ago
      deleted = 0
      deleted += PositionSnapshot.where("recorded_at < ?", cutoff).in_batches(of: 50_000).delete_all
      deleted += PollingStat.where("created_at < ?", cutoff).delete_all
      deleted += GpsJammingSnapshot.where("recorded_at < ?", cutoff).delete_all
      deleted += InternetTrafficSnapshot.where("created_at < ?", cutoff).delete_all
      deleted += SatelliteTleSnapshot.where("recorded_at < ?", 14.days.ago).delete_all
      deleted += Flight.where("updated_at < ?", 6.hours.ago).delete_all
      deleted += Ship.where("updated_at < ?", 24.hours.ago).delete_all
      deleted += Camera.where("expires_at < ?", Time.current).delete_all
      deleted += WeatherAlert.where("expires < ?", cutoff).delete_all
      deleted += Notam.where("effective_end < ?", cutoff).where.not(effective_end: nil).delete_all
      Rails.logger.info("GlobalPollerService: purged #{deleted} stale rows")
    rescue => e
      Rails.logger.error("GlobalPollerService purge error: #{e.message}")
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
