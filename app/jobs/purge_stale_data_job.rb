class PurgeStaleDataJob < ApplicationJob
  queue_as :background

  POSITION_SNAPSHOT_RETENTION = ENV.fetch("POSITION_SNAPSHOT_RETENTION_DAYS", 14).to_i.clamp(1, 90).days
  POLLING_STAT_RETENTION = ENV.fetch("POLLING_STAT_RETENTION_DAYS", 14).to_i.clamp(1, 90).days
  SIGNAL_SNAPSHOT_RETENTION = ENV.fetch("SIGNAL_SNAPSHOT_RETENTION_DAYS", 30).to_i.clamp(1, 180).days
  SATELLITE_TLE_RETENTION = ENV.fetch("SATELLITE_TLE_RETENTION_DAYS", 30).to_i.clamp(1, 180).days
  EXPIRED_OPERATIONAL_RETENTION = ENV.fetch("EXPIRED_OPERATIONAL_RETENTION_DAYS", 14).to_i.clamp(1, 90).days
  LIVE_FLIGHT_RETENTION = 6.hours
  LIVE_SHIP_RETENTION = 24.hours

  def perform
    deleted = {
      position_snapshots: PositionSnapshot.where("recorded_at < ?", POSITION_SNAPSHOT_RETENTION.ago).in_batches(of: 50_000).delete_all,
      polling_stats: PollingStat.where("created_at < ?", POLLING_STAT_RETENTION.ago).delete_all,
      gps_jamming_snapshots: GpsJammingSnapshot.where("recorded_at < ?", SIGNAL_SNAPSHOT_RETENTION.ago).delete_all,
      internet_traffic_snapshots: InternetTrafficSnapshot.where("created_at < ?", SIGNAL_SNAPSHOT_RETENTION.ago).delete_all,
      internet_attack_pair_snapshots: InternetAttackPairSnapshot.where("created_at < ?", SIGNAL_SNAPSHOT_RETENTION.ago).delete_all,
      satellite_tle_snapshots: SatelliteTleSnapshot.where("recorded_at < ?", SATELLITE_TLE_RETENTION.ago).delete_all,
      flights: Flight.where("updated_at < ?", LIVE_FLIGHT_RETENTION.ago).delete_all,
      ships: Ship.where("updated_at < ?", LIVE_SHIP_RETENTION.ago).delete_all,
      cameras: Camera.where("expires_at < ?", Time.current).delete_all,
      weather_alerts: WeatherAlert.where("expires < ?", EXPIRED_OPERATIONAL_RETENTION.ago).delete_all,
      notams: Notam.where("effective_end < ?", EXPIRED_OPERATIONAL_RETENTION.ago).where.not(effective_end: nil).delete_all,
    }

    Rails.logger.info("PurgeStaleDataJob: purged #{deleted.values.sum} stale rows #{deleted.inspect}")
  end
end
