class GlobalPollerService
  LOOP_INTERVAL = 5.seconds
  ENQUEUE_LOCK_SLACK = 5.seconds

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

  JOB_SCHEDULES = [
    { job: PollOpenskyJob, every: 30.seconds, offset: 0.seconds },
    { job: PollAdsbMilitaryJob, every: 15.seconds, offset: 5.seconds },
    { job: RefreshLiveTrainsJob, every: 30.seconds, offset: 10.seconds, conditional: :trains_layer_enabled? },
    { job: RefreshEarthquakesJob, every: 2.minutes, offset: 0.seconds },
    { job: PollAdsbRegionJob, every: 30.seconds, offset: 20.seconds, dynamic: :adsb_region },
    { job: RefreshNewsJob, every: 5.minutes, offset: 0.seconds },
    { job: RefreshRssNewsJob, every: 5.minutes, offset: 1.minute },
    { job: RefreshMultiNewsJob, every: 5.minutes, offset: 2.minutes },
    { job: EnrichNewsJob, every: 5.minutes, offset: 3.minutes },
    { job: RefreshNaturalEventsJob, every: 5.minutes, offset: 150.seconds },
    { job: RefreshInternetOutagesJob, every: 5.minutes, offset: 210.seconds },
    { job: RefreshConflictPulseSnapshotJob, every: 5.minutes, offset: 4.minutes },
    { job: RefreshCamerasJob, every: 5.minutes, offset: 270.seconds, dynamic: :camera_region },
    { job: RefreshWeatherAlertsJob, every: 10.minutes, offset: 0.seconds },
    { job: RefreshNotamsJob, every: 10.minutes, offset: 2.minutes },
    { job: RefreshFireHotspotsJob, every: 10.minutes, offset: 4.minutes },
    { job: RefreshChokepointsSnapshotJob, every: 10.minutes, offset: 6.minutes },
    { job: RefreshOntologyRelationshipsJob, every: 10.minutes, offset: 7.minutes },
    { job: RefreshInsightsSnapshotJob, every: 10.minutes, offset: 8.minutes },
    { job: RefreshInternetTrafficJob, every: 15.minutes, offset: 10.minutes },
    { job: RefreshGpsJammingJob, every: 15.minutes, offset: 12.minutes },
    { job: PersistYahooMarketSignalsJob, every: 1.minute, offset: 30.seconds },
    { job: RefreshCommodityPricesJob, every: 1.hour, offset: 0.minutes },
    { job: PurgeStaleDataJob, every: 1.hour, offset: 10.minutes },
    { job: RecheckStaleCamerasJob, every: 1.hour, offset: 20.minutes },
    { job: GenerateBriefJob, every: 1.hour, offset: 50.minutes, conditional: :brief_missing? },
    { job: RefreshAcledJob, every: 6.hours, offset: 0.minutes },
    { job: RefreshGeoconfirmedJob, every: 6.hours, offset: 15.minutes },
    { job: RefreshConflictEventsJob, every: 6.hours, offset: 30.minutes },
    { job: RefreshSatellitesJob, every: 6.hours, offset: 60.minutes },
    { job: RefreshAirportsJob, every: 12.hours, offset: 0.minutes },
    { job: RefreshPowerPlantsJob, every: 12.hours, offset: 90.minutes },
    { job: RefreshPipelinesJob, every: 12.hours, offset: 3.hours },
    { job: RefreshRailwaysJob, every: 12.hours, offset: 4.hours, conditional: :railways_layer_enabled? },
    { job: RefreshSubmarineCablesJob, every: 24.hours, offset: 0.minutes },
    { job: RefreshMilitaryBasesJob, every: 24.hours, offset: 6.hours },
    { job: RefreshCountryIndicatorsJob, every: 24.hours, offset: 8.hours },
    { job: RefreshTradeFlowsJob, every: 1.hour, offset: 9.minutes },
    { job: RefreshEnergyBalancesJob, every: 24.hours, offset: 10.hours },
    { job: RefreshSectorInputsJob, every: 24.hours, offset: 11.hours },
    { job: RefreshTradeLocationsJob, every: 7.days, offset: 12.hours },
    { job: RefreshSupplyChainDerivationsJob, every: 24.hours, offset: 13.hours },
    { job: RefreshSupplyChainOntologyJob, every: 24.hours, offset: 13.hours + 15.minutes },
    { job: RefreshPlaceGazetteerJob, every: 24.hours, offset: 14.hours },
  ].freeze

  LIVE_LAYER_CADENCES = {
    flights_global: 15.seconds,
    flights_military: 15.seconds,
    flights_regional_rotation: 30.seconds,
    trains: 30.seconds,
    ais_stream: :continuous,
    earthquakes: 2.minutes,
    fast_news: 5.minutes,
    news_enrichment: 5.minutes,
    conflict_pulse: 5.minutes,
    natural_events: 5.minutes,
    internet_outages: 5.minutes,
    cameras_rotation: 5.minutes,
    market_signals: 1.minute,
    weather_alerts: 10.minutes,
    notams: 10.minutes,
    fire_hotspots: 10.minutes,
    ontology_relationships: 10.minutes,
    insights: 10.minutes,
    chokepoints: 10.minutes,
  }.freeze

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
      enqueued_jobs = JOB_SCHEDULES.filter_map do |schedule|
        enqueue_schedule(schedule, now: now)
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

    def cadence_plan
      LIVE_LAYER_CADENCES
    end

    private

    def enqueue_schedule(schedule, now:)
      return unless schedule_enabled?(schedule)
      return unless due_now?(schedule, now)

      job = schedule.fetch(:job)
      interval = schedule.fetch(:every)
      offset = schedule.fetch(:offset, 0.seconds)
      slot_key = slot_for(now, interval, offset)
      label = schedule_label(schedule, now)
      suffix = schedule_suffix(schedule, now)
      args = schedule_args(schedule, now)

      return unless enqueue_once(
        job,
        slot_key,
        interval: interval,
        ttl: interval + ENQUEUE_LOCK_SLACK,
        key_suffix: suffix,
        args: args
      )

      label
    end

    def schedule_enabled?(schedule)
      conditional = schedule[:conditional]
      return true if conditional.blank?

      send(conditional)
    end

    def trains_layer_enabled?
      LayerAvailability.enabled?(:trains)
    end

    def railways_layer_enabled?
      LayerAvailability.enabled?(:railways)
    end

    def schedule_label(schedule, now)
      case schedule[:dynamic]
      when :adsb_region
        "PollAdsbRegionJob(#{current_adsb_region(now, schedule)[:name]})"
      when :camera_region
        "RefreshCamerasJob(#{current_camera_region(now, schedule)[:name]})"
      else
        schedule.fetch(:job).name
      end
    end

    def schedule_suffix(schedule, now)
      case schedule[:dynamic]
      when :adsb_region
        current_adsb_region(now, schedule)[:name]
      when :camera_region
        current_camera_region(now, schedule)[:name]
      else
        schedule[:key_suffix]
      end
    end

    def schedule_args(schedule, now)
      case schedule[:dynamic]
      when :adsb_region
        region = current_adsb_region(now, schedule)
        [region[:name], region[:lat], region[:lon]]
      when :camera_region
        region = current_camera_region(now, schedule)
        [
          {
            north: region[:north],
            south: region[:south],
            east: region[:east],
            west: region[:west],
          },
        ]
      else
        Array(schedule[:args])
      end
    end

    def current_adsb_region(now, schedule)
      ADSB_REGIONS[slot_index_for(now, schedule.fetch(:every), schedule.fetch(:offset, 0.seconds)) % ADSB_REGIONS.size]
    end

    def current_camera_region(now, schedule)
      CAMERA_REGIONS[slot_index_for(now, schedule.fetch(:every), schedule.fetch(:offset, 0.seconds)) % CAMERA_REGIONS.size]
    end

    def brief_missing?
      !Rails.cache.read(IntelligenceBriefService::CACHE_KEY)
    end

    def enqueue_once(job_class, slot_key, interval:, ttl:, key_suffix: nil, args: [])
      cache_key = dedupe_cache_key(job_class, slot_key, interval: interval, key_suffix: key_suffix)
      return false if Rails.cache.exist?(cache_key)

      Rails.cache.write(cache_key, "1", expires_in: dedupe_ttl(interval: interval, default_ttl: ttl))
      job_class.perform_later(*args)
      true
    rescue StandardError => e
      Rails.logger.warn("GlobalPollerService enqueue #{job_class.name}: #{e.message}")
      false
    end

    def dedupe_cache_key(job_class, slot_key, interval:, key_suffix: nil)
      if interval >= 1.minute
        ["poller", "pending", job_class.name, key_suffix].compact.join(":")
      else
        ["poller", slot_key, job_class.name, key_suffix].compact.join(":")
      end
    end

    def dedupe_ttl(interval:, default_ttl:)
      return default_ttl if interval < 1.minute

      interval + 1.minute
    end

    def slot_for(now, interval, offset = 0.seconds)
      "#{interval.to_i}:#{offset.to_i}:#{slot_index_for(now, interval, offset)}"
    end

    def slot_index_for(now, interval, offset = 0.seconds)
      ((now.to_i - offset.to_i) / interval.to_i)
    end

    def due_now?(schedule, now)
      interval = schedule.fetch(:every).to_i
      offset = schedule.fetch(:offset, 0.seconds).to_i
      ((now.to_i - offset) % interval) < LOOP_INTERVAL.to_i
    end

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

    def heartbeat_metadata(now:, poll_count:, enqueued_jobs:, error_message: nil)
      {
        "started_at" => PollerRuntimeState.status[:started_at]&.iso8601 || now.iso8601,
        "last_poll_at" => now.iso8601,
        "last_tick_at" => now.iso8601,
        "poll_count" => poll_count.to_i,
        "ais_mode" => ENV["AISSTREAM_API_KEY"].present? ? "stream" : "disabled",
        "ais_running" => AisStreamService.running?,
        "scheduler" => runtime_owner,
        "job_names" => enqueued_jobs,
        "last_error" => error_message,
      }.compact
    end

    def runtime_owner
      dyno = ENV["DYNO"].to_s
      return "worker" if dyno.start_with?("worker")

      "poller"
    end
  end
end
