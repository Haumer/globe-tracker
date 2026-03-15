module SnapshotRecorder
  # Minimum thresholds to record a new snapshot.
  # Tuned for 7-day retention within 10GB DB budget (~4M rows/day target).
  LAT_LNG_THRESHOLD = 0.005  # ~556 meters — still smooth for playback
  ALT_THRESHOLD     = 150    # meters — ignore minor altitude wobble
  HEADING_THRESHOLD = 8      # degrees — straight-line segments are interpolatable
  SPEED_THRESHOLD   = 15     # m/s — ignore minor speed fluctuations

  # Call after upserting flights to record position snapshots
  def record_flight_snapshots(records)
    return if records.blank?

    now = Time.current
    entity_ids = records.filter_map { |r| r[:icao24] if r[:latitude] && r[:longitude] }
    last_snapshots = fetch_last_snapshots("flight", entity_ids)

    snapshots = records.filter_map do |r|
      next if r[:latitude].nil? || r[:longitude].nil?
      next if snapshot_unchanged?(last_snapshots[r[:icao24]], r)

      {
        entity_type: "flight",
        entity_id: r[:icao24],
        callsign: r[:callsign],
        latitude: r[:latitude],
        longitude: r[:longitude],
        altitude: r[:altitude],
        heading: r[:heading],
        speed: r[:speed],
        vertical_rate: r[:vertical_rate],
        on_ground: r[:on_ground],
        extra: { mil: r[:military] ? 1 : nil, sq: r[:squawk], src: r[:source] }.compact.to_json,
        recorded_at: now,
      }
    end

    PositionSnapshot.insert_all(snapshots) if snapshots.any?
  rescue => e
    Rails.logger.error("Snapshot recording error: #{e.message}")
  end

  # Call after upserting ships to record position snapshots
  def record_ship_snapshots(records)
    return if records.blank?

    now = Time.current
    entity_ids = records.filter_map { |r| r[:mmsi] if r[:latitude] && r[:longitude] }
    last_snapshots = fetch_last_snapshots("ship", entity_ids)

    snapshots = records.filter_map do |r|
      next if r[:latitude].nil? || r[:longitude].nil?
      next if snapshot_unchanged?(last_snapshots[r[:mmsi]], r)

      {
        entity_type: "ship",
        entity_id: r[:mmsi],
        callsign: r[:name],
        latitude: r[:latitude],
        longitude: r[:longitude],
        altitude: nil,
        heading: r[:heading],
        speed: r[:speed],
        vertical_rate: nil,
        on_ground: nil,
        extra: { ship_type: r[:ship_type], destination: r[:destination], flag: r[:flag] }.compact.to_json,
        recorded_at: now,
      }
    end

    PositionSnapshot.insert_all(snapshots) if snapshots.any?
  rescue => e
    Rails.logger.error("Ship snapshot recording error: #{e.message}")
  end

  private

  # Batch-fetch the most recent snapshot per entity to compare against
  def fetch_last_snapshots(entity_type, entity_ids)
    return {} if entity_ids.blank?

    rows = PositionSnapshot
      .where(entity_type: entity_type, entity_id: entity_ids)
      .where("recorded_at > ?", 10.minutes.ago)
      .select("DISTINCT ON (entity_id) entity_id, latitude, longitude, altitude, heading, speed, recorded_at")
      .order(:entity_id, recorded_at: :desc)

    rows.each_with_object({}) do |row, hash|
      hash[row.entity_id] = row
    end
  end

  MAX_SNAPSHOT_AGE = 300 # Record if last snapshot is older than 5 min; moving entities still record on position change

  def snapshot_unchanged?(last, record)
    return false unless last # no previous record — always insert

    # Always record periodically so playback has consistent data
    return false if last.respond_to?(:recorded_at) && last.recorded_at && last.recorded_at < MAX_SNAPSHOT_AGE.seconds.ago

    pos_same = (last.latitude - record[:latitude]).abs < LAT_LNG_THRESHOLD &&
               (last.longitude - record[:longitude]).abs < LAT_LNG_THRESHOLD &&
               (!record[:altitude] || !last.altitude || (last.altitude - record[:altitude]).abs < ALT_THRESHOLD)

    # Position hasn't moved — skip regardless of heading/speed jitter
    return true if pos_same

    # Position moved but heading+speed unchanged — straight-line, interpolatable
    hdg_same = !record[:heading] || !last.heading || heading_delta(last.heading, record[:heading]) < HEADING_THRESHOLD
    spd_same = !record[:speed] || !last.speed || (last.speed - record[:speed]).abs < SPEED_THRESHOLD

    hdg_same && spd_same
  end

  # Handle heading wraparound (e.g. 359° → 1° = 2° delta, not 358°)
  def heading_delta(a, b)
    d = (a - b).abs
    d > 180 ? 360 - d : d
  end
end
