class AnomalyDetector
  REGIONS = {
    "Europe"       => { lamin: 35, lamax: 72, lomin: -25, lomax: 40 },
    "Middle East"  => { lamin: 12, lamax: 45, lomin: 25, lomax: 65 },
    "East Asia"    => { lamin: 18, lamax: 55, lomin: 90, lomax: 150 },
    "North America"=> { lamin: 10, lamax: 85, lomin: -170, lomax: -50 },
    "Africa"       => { lamin: -35, lamax: 37, lomin: -20, lomax: 55 },
  }.freeze

  def self.detect
    new.detect
  end

  def detect
    anomalies = []
    anomalies.concat(detect_emergency_flights)
    anomalies.concat(detect_military_spikes)
    anomalies.concat(detect_new_jamming)
    anomalies.concat(detect_significant_earthquakes)
    anomalies.sort_by { |a| -a[:severity] }
  end

  private

  # ── Emergency squawk codes (highest priority) ─────────────────

  def detect_emergency_flights
    squawk_labels = { "7500" => "Hijack", "7600" => "Radio failure", "7700" => "Emergency" }
    flights = Flight.where(squawk: %w[7500 7600 7700]).where.not(latitude: nil)

    flights.map do |f|
      {
        type: "emergency_flight",
        severity: 10,
        icon: "fa-triangle-exclamation",
        color: "#f44336",
        title: "#{squawk_labels[f.squawk]}: #{f.callsign || f.icao24}",
        detail: "Squawk #{f.squawk} at FL#{((f.altitude || 0) / 30.48).round(-1) / 10}",
        lat: f.latitude,
        lng: f.longitude,
        entity_type: "flight",
        entity_id: f.icao24,
      }
    end
  end

  # ── Military flight concentration spikes ──────────────────────

  def detect_military_spikes
    anomalies = []

    REGIONS.each do |name, bounds|
      flights = Flight.within_bounds(bounds).where(military: true).where.not(latitude: nil)
      current = flights.count
      next if current < 10

      # Compare against historical average from snapshots
      avg = average_military_count(bounds)
      next if avg.nil? || avg < 5

      ratio = current.to_f / avg
      next unless ratio > 3.0

      # Use actual centroid of military flights, not region center
      centroid = flights.pick(Arel.sql("AVG(latitude)"), Arel.sql("AVG(longitude)"))

      anomalies << {
        type: "military_spike",
        severity: [ratio * 2, 9].min.round(1),
        icon: "fa-jet-fighter",
        color: "#ef5350",
        title: "Military flight spike in #{name}",
        detail: "#{current} active (#{ratio.round(1)}x normal avg of #{avg.round(0)})",
        lat: centroid[0],
        lng: centroid[1],
      }
    end

    anomalies
  end

  def average_military_count(bounds)
    # Sample hourly military counts from snapshots over last 24h
    counts = []
    24.times do |h|
      from = (h + 1).hours.ago
      to = h.hours.ago
      c = PositionSnapshot.flights
            .in_range(from, to)
            .within_bounds(bounds)
            .where("extra::jsonb @> ?", { military: true }.to_json)
            .select(:entity_id).distinct.count
      counts << c
    end
    return nil if counts.empty?
    counts.sum.to_f / counts.size
  end

  # ── New GPS jamming zones ─────────────────────────────────────

  def detect_new_jamming
    # Cells with high jamming in the last hour
    recent = GpsJammingSnapshot
      .where("recorded_at > ?", 1.hour.ago)
      .where("percentage > 10")
      .select("DISTINCT ON (cell_lat, cell_lng) cell_lat, cell_lng, percentage, level, recorded_at")
      .order("cell_lat, cell_lng, recorded_at DESC")

    # Cells that were active 2-6 hours ago
    old_cells = GpsJammingSnapshot
      .where(recorded_at: 6.hours.ago..1.hour.ago)
      .where("percentage > 10")
      .pluck(:cell_lat, :cell_lng)
      .map { |lat, lng| "#{lat.round(1)},#{lng.round(1)}" }
      .to_set

    recent.filter_map do |snap|
      key = "#{snap.cell_lat.round(1)},#{snap.cell_lng.round(1)}"
      next if old_cells.include?(key)

      {
        type: "new_jamming",
        severity: snap.percentage > 50 ? 8 : 6,
        icon: "fa-satellite-dish",
        color: "#ff9800",
        title: "New GPS jamming zone detected",
        detail: "#{snap.percentage.round(1)}% degradation (#{snap.level})",
        lat: snap.cell_lat,
        lng: snap.cell_lng,
      }
    end
  end

  # ── Significant earthquakes ───────────────────────────────────

  def detect_significant_earthquakes
    Earthquake.where("event_time > ?", 1.hour.ago)
              .where("magnitude >= 5.0")
              .order(magnitude: :desc)
              .limit(5)
              .map do |eq|
      {
        type: "major_earthquake",
        severity: [eq.magnitude, 10].min,
        icon: "fa-house-crack",
        color: "#ff7043",
        title: "M#{eq.magnitude} #{eq.title}",
        detail: "Depth #{eq.depth&.round(1)}km, #{eq.tsunami ? 'tsunami warning' : 'no tsunami'}",
        lat: eq.latitude,
        lng: eq.longitude,
        entity_type: "earthquake",
      }
    end
  end
end
