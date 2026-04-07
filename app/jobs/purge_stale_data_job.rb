class PurgeStaleDataJob < ApplicationJob
  queue_as :background

  RETENTION = 3.days

  def perform
    cutoff = RETENTION.ago
    deleted = 0
    deleted += PositionSnapshot.where("recorded_at < ?", cutoff).in_batches(of: 50_000).delete_all
    deleted += PollingStat.where("created_at < ?", cutoff).delete_all
    deleted += GpsJammingSnapshot.where("recorded_at < ?", cutoff).delete_all
    deleted += InternetTrafficSnapshot.where("created_at < ?", cutoff).delete_all
    deleted += InternetAttackPairSnapshot.where("created_at < ?", cutoff).delete_all
    deleted += SatelliteTleSnapshot.where("recorded_at < ?", 14.days.ago).delete_all
    deleted += Flight.where("updated_at < ?", 6.hours.ago).delete_all
    deleted += Ship.where("updated_at < ?", 24.hours.ago).delete_all
    deleted += Camera.where("expires_at < ?", Time.current).delete_all
    deleted += WeatherAlert.where("expires < ?", cutoff).delete_all
    deleted += Notam.where("effective_end < ?", cutoff).where.not(effective_end: nil).delete_all
    Rails.logger.info("PurgeStaleDataJob: purged #{deleted} stale rows")
  end
end
