namespace :timeline do
  desc "Backfill timeline_events from existing data"
  task backfill: :environment do
    now = Time.current

    # Earthquakes
    count = 0
    Earthquake.where.not(latitude: nil, longitude: nil).find_each do |eq|
      TimelineEvent.upsert(
        { event_type: "earthquake", eventable_type: "Earthquake", eventable_id: eq.id,
          latitude: eq.latitude, longitude: eq.longitude, recorded_at: eq.event_time || eq.created_at,
          created_at: now, updated_at: now },
        unique_by: [:eventable_type, :eventable_id]
      )
      count += 1
    end
    puts "Backfilled #{count} earthquakes"

    # Natural events
    count = 0
    NaturalEvent.where.not(latitude: nil, longitude: nil).find_each do |ev|
      TimelineEvent.upsert(
        { event_type: "natural_event", eventable_type: "NaturalEvent", eventable_id: ev.id,
          latitude: ev.latitude, longitude: ev.longitude, recorded_at: ev.event_date || ev.created_at,
          created_at: now, updated_at: now },
        unique_by: [:eventable_type, :eventable_id]
      )
      count += 1
    end
    puts "Backfilled #{count} natural events"

    # News events
    count = 0
    NewsEvent.where.not(latitude: nil, longitude: nil).find_each do |ne|
      TimelineEvent.upsert(
        { event_type: "news", eventable_type: "NewsEvent", eventable_id: ne.id,
          latitude: ne.latitude, longitude: ne.longitude, recorded_at: ne.published_at || ne.created_at,
          created_at: now, updated_at: now },
        unique_by: [:eventable_type, :eventable_id]
      )
      count += 1
    end
    puts "Backfilled #{count} news events"

    # GPS jamming snapshots (medium/high only)
    count = 0
    GpsJammingSnapshot.where(level: %w[medium high]).find_each do |gj|
      TimelineEvent.upsert(
        { event_type: "gps_jamming", eventable_type: "GpsJammingSnapshot", eventable_id: gj.id,
          latitude: gj.cell_lat, longitude: gj.cell_lng, recorded_at: gj.recorded_at,
          created_at: now, updated_at: now },
        unique_by: [:eventable_type, :eventable_id]
      )
      count += 1
    end
    puts "Backfilled #{count} GPS jamming snapshots"

    # Internet outages (no lat/lng)
    count = 0
    InternetOutage.find_each do |io|
      TimelineEvent.upsert(
        { event_type: "internet_outage", eventable_type: "InternetOutage", eventable_id: io.id,
          latitude: nil, longitude: nil, recorded_at: io.started_at || io.created_at,
          created_at: now, updated_at: now },
        unique_by: [:eventable_type, :eventable_id]
      )
      count += 1
    end
    puts "Backfilled #{count} internet outages"

    puts "Done! Total timeline events: #{TimelineEvent.count}"
  end

  desc "Purge timeline events older than N hours (default 48)"
  task purge: :environment do
    hours = (ENV["HOURS"] || 48).to_i
    deleted = TimelineEvent.where("recorded_at < ?", hours.hours.ago).delete_all
    puts "Purged #{deleted} timeline events older than #{hours}h"
  end
end
