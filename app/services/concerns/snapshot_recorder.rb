module SnapshotRecorder
  # Call after upserting flights to record position snapshots
  def record_flight_snapshots(records)
    return if records.blank?

    now = Time.current
    snapshots = records.filter_map do |r|
      next if r[:latitude].nil? || r[:longitude].nil?

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
        extra: { source: r[:source], registration: r[:registration], aircraft_type: r[:aircraft_type], origin_country: r[:origin_country] }.compact.to_json,
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
    snapshots = records.filter_map do |r|
      next if r[:latitude].nil? || r[:longitude].nil?

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
end
