namespace :db do
  desc "Purge stale data to keep DB within 10GB budget (7-day retention)"
  task purge: :environment do
    puts "Purging stale data..."

    # Position snapshots: 7-day retention (biggest table by far)
    cutoff = 7.days.ago
    deleted = PositionSnapshot.where("recorded_at < ?", cutoff).delete_all
    puts "  position_snapshots: deleted #{deleted} rows older than #{cutoff}"

    # Polling stats: 7-day retention
    deleted = PollingStat.where("created_at < ?", cutoff).delete_all
    puts "  polling_stats: deleted #{deleted} rows"

    # Timeline events: 30-day retention
    deleted = TimelineEvent.where("recorded_at < ?", 30.days.ago).delete_all
    puts "  timeline_events: deleted #{deleted} rows"

    # GPS jamming snapshots: 7-day retention
    deleted = GpsJammingSnapshot.where("recorded_at < ?", cutoff).delete_all
    puts "  gps_jamming_snapshots: deleted #{deleted} rows"

    # Internet traffic snapshots: 7-day retention
    deleted = InternetTrafficSnapshot.where("created_at < ?", cutoff).delete_all
    puts "  internet_traffic_snapshots: deleted #{deleted} rows"

    # Satellite TLE snapshots: 14-day retention
    deleted = SatelliteTleSnapshot.where("recorded_at < ?", 14.days.ago).delete_all
    puts "  satellite_tle_snapshots: deleted #{deleted} rows"

    # Expired cameras
    deleted = Camera.where("expires_at < ?", Time.current).delete_all
    puts "  cameras (expired): deleted #{deleted} rows"

    # Stale flights/ships not updated recently
    deleted = Flight.where("updated_at < ?", 6.hours.ago).delete_all
    puts "  flights (stale): deleted #{deleted} rows"

    deleted = Ship.where("updated_at < ?", 24.hours.ago).delete_all
    puts "  ships (stale): deleted #{deleted} rows"

    # Old news events: 30-day retention
    deleted = NewsEvent.where("published_at < ?", 30.days.ago).where("published_at IS NOT NULL").delete_all
    puts "  news_events (>30d): deleted #{deleted} rows"

    # Old weather alerts (expired > 7 days ago)
    deleted = WeatherAlert.where("expires < ?", cutoff).delete_all
    puts "  weather_alerts (expired): deleted #{deleted} rows"

    # Old NOTAMs (ended > 7 days ago)
    deleted = Notam.where("effective_end < ?", cutoff).where.not(effective_end: nil).delete_all
    puts "  notams (ended): deleted #{deleted} rows"

    # Report DB size
    size = ActiveRecord::Base.connection.execute("SELECT pg_size_pretty(pg_database_size(current_database())) as s").first["s"]
    puts "\nDB size after purge: #{size}"
    puts "Done."
  end
end
