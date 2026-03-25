class GlobalPollerService
  TICK_INTERVAL = 10.minutes
  HOURLY_INTERVAL = 1.hour
  ENQUEUE_LOCK_SLACK = 2.minutes

  FAST_JOBS = [
    PollOpenskyJob,
    PollAdsbMilitaryJob,
    RefreshEarthquakesJob,
    RefreshNewsJob,
    RefreshMultiNewsJob,
    RefreshRssNewsJob,
    RefreshFireHotspotsJob,
    RefreshNaturalEventsJob,
    RefreshInternetOutagesJob,
    RefreshInternetTrafficJob,
    RefreshWeatherAlertsJob,
    RefreshNotamsJob,
    RefreshLiveTrainsJob,
    EnrichNewsJob,
    RefreshConflictPulseSnapshotJob,
    RefreshChokepointsSnapshotJob,
    RefreshInsightsSnapshotJob,
  ].freeze

  HOURLY_JOBS = [
    RefreshConflictEventsJob,
    RefreshAcledJob,
    RefreshGpsJammingJob,
    RefreshCommodityPricesJob,
    RefreshPipelinesJob,
    RefreshRailwaysJob,
    RefreshPowerPlantsJob,
    RefreshSubmarineCablesJob,
    RefreshSatellitesJob,
    RefreshAirportsJob,
    RefreshMilitaryBasesJob,
    PurgeStaleDataJob,
    RecheckStaleCamerasJob,
  ].freeze

  ADSB_REGIONS = [
    { name: "europe", lat: 50, lon: 10 },
    { name: "na-east", lat: 38, lon: -80 },
    { name: "na-west", lat: 37, lon: -120 },
    { name: "mideast", lat: 28, lon: 47 },
    { name: "east-asia", lat: 35, lon: 135 },
    { name: "se-asia", lat: 5, lon: 105 },
    { name: "oceania", lat: -30, lon: 150 },
    { name: "south-am", lat: -20, lon: -50 },
    { name: "africa", lat: 5, lon: 25 },
    { name: "india", lat: 22, lon: 78 },
  ].freeze

  CAMERA_REGIONS = [
    { name: "europe-west", north: 60, south: 35, east: 15, west: -10 },
    { name: "europe-east", north: 60, south: 35, east: 40, west: 15 },
    { name: "na-east", north: 50, south: 25, east: -65, west: -90 },
    { name: "na-west", north: 50, south: 25, east: -90, west: -125 },
    { name: "east-asia", north: 45, south: 20, east: 145, west: 100 },
    { name: "se-asia", north: 20, south: -10, east: 130, west: 95 },
    { name: "south-am", north: 10, south: -40, east: -35, west: -80 },
    { name: "mideast", north: 40, south: 15, east: 60, west: 25 },
    { name: "oceania", north: -10, south: -45, east: 180, west: 110 },
    { name: "africa", north: 35, south: -35, east: 50, west: -20 },
  ].freeze

  class << self
    def tick!(now: Time.current)
      desired_state = PollerRuntimeState.desired_state

      case desired_state
      when "paused"
        return record_skip!("paused", now: now)
      when "stopped"
        return record_skip!("stopped", now: now)
      end

      poll_count = PollerRuntimeState.increment_poll_count!(now: now)
      tick_slot = slot_index_for(now, TICK_INTERVAL)
      enqueued_jobs = []

      FAST_JOBS.each do |job_class|
        enqueued_jobs << job_class.name if enqueue_once(job_class, slot_for(now, TICK_INTERVAL), ttl: TICK_INTERVAL + ENQUEUE_LOCK_SLACK)
      end

      enqueued_jobs << "PollAdsbRegionJob(#{current_adsb_region(tick_slot)[:name]})" if enqueue_adsb_region(now: now, tick_slot: tick_slot)
      enqueued_jobs << "RefreshCamerasJob(#{current_camera_region(tick_slot)[:name]})" if enqueue_camera_refresh(now: now, tick_slot: tick_slot)

      if hourly_slot_due?(now)
        HOURLY_JOBS.each do |job_class|
          enqueued_jobs << job_class.name if enqueue_once(job_class, slot_for(now, HOURLY_INTERVAL), ttl: HOURLY_INTERVAL + ENQUEUE_LOCK_SLACK)
        end
        enqueued_jobs << GenerateBriefJob.name if enqueue_brief_generation(now: now)
      end

      PollerRuntimeState.heartbeat!(
        reported_state: "running",
        metadata: heartbeat_metadata(
          now: now,
          poll_count: poll_count,
          enqueued_jobs: enqueued_jobs
        )
      )

      {
        status: "running",
        poll_count: poll_count,
        jobs_enqueued: enqueued_jobs.size,
        job_names: enqueued_jobs,
      }
    rescue StandardError => e
      PollerRuntimeState.heartbeat!(
        reported_state: "error",
        metadata: heartbeat_metadata(
          now: now,
          poll_count: PollerRuntimeState.status[:poll_count],
          enqueued_jobs: [],
          error_message: "#{e.class}: #{e.message}"
        )
      )
      raise
    end

    def status
      PollerRuntimeState.status
    end

    def running?
      status[:running]
    end

    def paused?
      status[:paused]
    end

    def pause
      PollerRuntimeState.request_pause!
    end

    def resume
      PollerRuntimeState.request_resume!
    end

    def stop
      PollerRuntimeState.request_stop!
    end

    private

    def record_skip!(state, now:)
      PollerRuntimeState.heartbeat!(
        reported_state: state,
        metadata: heartbeat_metadata(
          now: now,
          poll_count: PollerRuntimeState.status[:poll_count],
          enqueued_jobs: []
        )
      )

      {
        status: state,
        poll_count: PollerRuntimeState.status[:poll_count],
        jobs_enqueued: 0,
        job_names: [],
      }
    end

    def enqueue_adsb_region(now:, tick_slot:)
      region = current_adsb_region(tick_slot)
      enqueue_once(
        PollAdsbRegionJob,
        slot_for(now, TICK_INTERVAL),
        ttl: TICK_INTERVAL + ENQUEUE_LOCK_SLACK,
        key_suffix: region[:name],
        args: [region[:name], region[:lat], region[:lon]]
      )
    end

    def enqueue_camera_refresh(now:, tick_slot:)
      region = current_camera_region(tick_slot)
      enqueue_once(
        RefreshCamerasJob,
        slot_for(now, TICK_INTERVAL),
        ttl: TICK_INTERVAL + ENQUEUE_LOCK_SLACK,
        key_suffix: region[:name],
        args: [
          {
            north: region[:north],
            south: region[:south],
            east: region[:east],
            west: region[:west],
          },
        ]
      )
    rescue StandardError => e
      Rails.logger.warn("GlobalPollerService camera tick: #{e.message}")
      false
    end

    def enqueue_brief_generation(now:)
      return false if Rails.cache.read(IntelligenceBriefService::CACHE_KEY)

      enqueue_once(
        GenerateBriefJob,
        slot_for(now, HOURLY_INTERVAL),
        ttl: HOURLY_INTERVAL + ENQUEUE_LOCK_SLACK
      )
    end

    def enqueue_once(job_class, slot_key, ttl:, key_suffix: nil, args: [])
      cache_key = [ "scheduler", slot_key, job_class.name, key_suffix ].compact.join(":")
      return false if Rails.cache.exist?(cache_key)

      Rails.cache.write(cache_key, "1", expires_in: ttl)

      job_class.perform_later(*args)
      true
    rescue StandardError => e
      Rails.logger.warn("GlobalPollerService enqueue #{job_class.name}: #{e.message}")
      job_class.perform_later(*args)
      true
    end

    def current_adsb_region(tick_slot)
      ADSB_REGIONS[tick_slot.to_i % ADSB_REGIONS.size]
    end

    def current_camera_region(tick_slot)
      CAMERA_REGIONS[tick_slot.to_i % CAMERA_REGIONS.size]
    end

    def slot_for(now, interval)
      "#{interval.to_i}:#{slot_index_for(now, interval)}"
    end

    def slot_index_for(now, interval)
      now.to_i / interval.to_i
    end

    def hourly_slot_due?(now)
      current_slot = slot_for(now, HOURLY_INTERVAL)
      Rails.cache.read("scheduler:last_hourly_slot") != current_slot
    ensure
      Rails.cache.write("scheduler:last_hourly_slot", current_slot, expires_in: HOURLY_INTERVAL + ENQUEUE_LOCK_SLACK) if current_slot.present?
    end

    def heartbeat_metadata(now:, poll_count:, enqueued_jobs:, error_message: nil)
      {
        "started_at" => PollerRuntimeState.status[:started_at]&.iso8601 || now.iso8601,
        "last_poll_at" => now.iso8601,
        "last_tick_at" => now.iso8601,
        "poll_count" => poll_count.to_i,
        "ais_mode" => "disabled",
        "ais_running" => false,
        "scheduler" => "heroku",
        "job_names" => enqueued_jobs,
        "last_error" => error_message,
      }.compact
    end
  end
end
