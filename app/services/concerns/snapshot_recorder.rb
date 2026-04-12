module SnapshotRecorder
  # Minimum thresholds to record a new snapshot.
  # Balance: frequent enough for smooth playback, sparse enough for the storage budget.
  LAT_LNG_THRESHOLD = 0.002  # ~222 meters — smooth playback at cruise speed
  ALT_THRESHOLD     = 100    # meters
  HEADING_THRESHOLD = 3      # degrees — capture course corrections
  SPEED_THRESHOLD   = 10     # m/s

  # Ships move slowly and there are 22K+ of them — wider thresholds to cut volume ~5x
  SHIP_LAT_LNG_THRESHOLD = 0.01   # ~1.1 km — ships move slowly, still smooth playback
  SHIP_HEADING_THRESHOLD = 5      # degrees
  SHIP_SPEED_THRESHOLD   = 15     # m/s
  SHIP_MAX_SNAPSHOT_AGE  = 300    # 5 min — ships don't need 60s granularity

  # Call after upserting flights to record position snapshots
  def record_flight_snapshots(records)
    return if records.blank?

    now = Time.current
    entity_ids = records.filter_map { |r| r[:icao24] if r[:latitude] && r[:longitude] }
    last_snapshots = fetch_last_snapshots("flight", entity_ids)

    snapshots = records.filter_map do |r|
      next if r[:latitude].nil? || r[:longitude].nil?
      next if snapshot_unchanged?(last_snapshots[r[:icao24]], r, entity_type: "flight")

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
      next if snapshot_unchanged?(last_snapshots[r[:mmsi]], r, entity_type: "ship")

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

  MAX_SNAPSHOT_AGE = 60 # Record at least every 60s so playback has consistent frames

  def snapshot_unchanged?(last, record, entity_type: "flight")
    return false unless last # no previous record — always insert

    is_ship = entity_type == "ship"
    max_age = is_ship ? SHIP_MAX_SNAPSHOT_AGE : MAX_SNAPSHOT_AGE
    ll_thresh = is_ship ? SHIP_LAT_LNG_THRESHOLD : LAT_LNG_THRESHOLD
    hdg_thresh = is_ship ? SHIP_HEADING_THRESHOLD : HEADING_THRESHOLD
    spd_thresh = is_ship ? SHIP_SPEED_THRESHOLD : SPEED_THRESHOLD

    # Always record periodically so playback has consistent data
    return false if last.respond_to?(:recorded_at) && last.recorded_at && last.recorded_at < max_age.seconds.ago

    pos_same = (last.latitude - record[:latitude]).abs < ll_thresh &&
               (last.longitude - record[:longitude]).abs < ll_thresh &&
               (!record[:altitude] || !last.altitude || (last.altitude - record[:altitude]).abs < ALT_THRESHOLD)

    # Position hasn't moved — skip regardless of heading/speed jitter
    return true if pos_same

    # Position moved but heading+speed unchanged — straight-line, interpolatable
    hdg_same = !record[:heading] || !last.heading || heading_delta(last.heading, record[:heading]) < hdg_thresh
    spd_same = !record[:speed] || !last.speed || (last.speed - record[:speed]).abs < spd_thresh

    hdg_same && spd_same
  end

  # Handle heading wraparound (e.g. 359° → 1° = 2° delta, not 358°)
  def heading_delta(a, b)
    d = (a - b).abs
    d > 180 ? 360 - d : d
  end
end
