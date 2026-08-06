# Single source of truth for how much history the app keeps on disk.
#
# This is deliberately NOT related to polling cadence. How often a source is
# queried varies per source and lives in GlobalPollerService::JOB_SCHEDULES
# (15s for military ADS-B, 24h for submarine cables). Retention is the other
# axis: however fast a table fills, it keeps the same rolling window.
module DataRetention
  DEFAULT_DAYS = 14
  MIN_DAYS = 1
  MAX_DAYS = 90

  # Live-state tables key one row per vehicle (icao24 / mmsi) and are upserted
  # in place, so they hold the *current* position rather than history. Keeping
  # them for the full window would leave fortnight-old aircraft on a live map.
  # Their history is in position_snapshots, which does get the full window.
  LIVE_FLIGHT_WINDOW = 6.hours
  LIVE_SHIP_WINDOW = 24.hours

  class << self
    def days
      ENV.fetch("DATA_RETENTION_DAYS", DEFAULT_DAYS).to_i.clamp(MIN_DAYS, MAX_DAYS)
    end

    def window
      days.days
    end

    def cutoff(now: Time.current)
      now - window
    end
  end
end
