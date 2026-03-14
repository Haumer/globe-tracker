class CrossLayerAnalyzer
  PROXIMITY_KM = 200

  def self.analyze
    new.analyze
  end

  def analyze
    insights = []

    # Hardcoded domain-specific rules (precise, high-confidence)
    insights.concat(earthquake_infrastructure_threats)
    insights.concat(jamming_flight_impacts)
    insights.concat(conflict_military_surge)
    insights.concat(fire_infrastructure_threats)
    insights.concat(cable_outage_correlations)

    # General-purpose spatiotemporal convergence detection
    # Finds multi-layer hotspots that hardcoded rules don't cover
    convergences = ConvergenceDetector.detect
    # Deduplicate: skip convergences that overlap with existing insights (same cell)
    existing_cells = insights.map { |i| cell_key(i[:lat], i[:lng]) }.to_set
    convergences.each do |c|
      key = cell_key(c[:lat], c[:lng])
      insights << c unless existing_cells.include?(key)
    end

    insights.sort_by { |i| -severity_score(i[:severity]) }
  end

  private

  # ── Earthquakes threatening infrastructure ────────────────────

  def earthquake_infrastructure_threats
    quakes = Earthquake.where("event_time > ? AND magnitude >= 4.5", 24.hours.ago)
    insights = []

    quakes.find_each do |eq|
      bounds = bbox(eq.latitude, eq.longitude, eq.magnitude > 6 ? 300 : 150)

      # Check cables
      cables = cables_in_bounds(bounds)
      plants = PowerPlant.within_bounds(bounds)
      nuclear = plants.where(primary_fuel: "Nuclear")

      next if cables.empty? && plants.count == 0

      detail_parts = []
      detail_parts << "#{cables.size} submarine cable#{"s" unless cables.size == 1}" if cables.any?
      detail_parts << "#{plants.count} power plant#{"s" unless plants.count == 1}" if plants.any?
      detail_parts << "#{nuclear.count} NUCLEAR" if nuclear.any?

      severity = if nuclear.any? && eq.magnitude >= 6
        "critical"
      elsif nuclear.any? || (cables.size >= 2 && eq.magnitude >= 5.5)
        "high"
      else
        "medium"
      end

      insights << {
        type: "earthquake_infrastructure",
        severity: severity,
        title: "M#{eq.magnitude} earthquake threatens #{detail_parts.join(" and ")}",
        description: eq.title,
        lat: eq.latitude,
        lng: eq.longitude,
        entities: {
          earthquake: { id: eq.external_id, magnitude: eq.magnitude },
          cables: cables.map { |c| { name: c.name, id: c.cable_id } }.first(5),
          plants: plants.limit(5).map { |p| { name: p.name, fuel: p.primary_fuel, capacity: p.capacity_mw } },
        },
        detected_at: Time.current.iso8601,
      }
    end

    insights
  end

  # ── GPS jamming affecting flights ─────────────────────────────

  def jamming_flight_impacts
    jamming_zones = GpsJammingSnapshot.where("recorded_at > ? AND percentage > 10", 1.hour.ago)
      .select("cell_lat, cell_lng, MAX(percentage) as max_pct, MAX(level) as max_level")
      .group(:cell_lat, :cell_lng)

    insights = []
    jamming_zones.each do |zone|
      bounds = bbox(zone.cell_lat, zone.cell_lng, 150)
      flights = Flight.within_bounds(bounds)
      total = flights.count
      next if total == 0

      military = flights.where(military: true).count
      affected_countries = flights.distinct.pluck(:origin_country).compact.first(5)

      severity = zone.max_pct.to_f > 30 ? "high" : "medium"
      severity = "critical" if military > 5

      insights << {
        type: "jamming_flights",
        severity: severity,
        title: "GPS jamming (#{zone.max_pct.to_f.round(0)}%) affecting #{total} flight#{"s" unless total == 1}",
        description: "#{military} military, #{total - military} civilian in #{zone.max_level} jamming zone",
        lat: zone.cell_lat,
        lng: zone.cell_lng,
        entities: {
          jamming: { percentage: zone.max_pct.to_f, level: zone.max_level },
          flights: { total: total, military: military, countries: affected_countries },
        },
        detected_at: Time.current.iso8601,
      }
    end

    insights
  end

  # ── Conflict zones with military flight surge ─────────────────

  def conflict_military_surge
    recent_conflicts = ConflictEvent.where("date_end IS NULL OR date_end >= ?", 30.days.ago)
      .select("AVG(latitude) as avg_lat, AVG(longitude) as avg_lng, conflict_name, COUNT(*) as event_count")
      .group(:conflict_name)
      .having("COUNT(*) >= 3")

    insights = []
    recent_conflicts.each do |cluster|
      next unless cluster.avg_lat && cluster.avg_lng

      bounds = bbox(cluster.avg_lat, cluster.avg_lng, PROXIMITY_KM)
      mil_flights = Flight.within_bounds(bounds).where(military: true)
      mil_count = mil_flights.count
      next if mil_count < 3

      callsigns = mil_flights.limit(10).pluck(:callsign).compact
      countries = mil_flights.distinct.pluck(:origin_country).compact

      insights << {
        type: "conflict_military",
        severity: mil_count > 10 ? "high" : "medium",
        title: "#{mil_count} military flights near #{cluster.conflict_name}",
        description: "#{cluster.event_count.to_i} conflict events in area, #{countries.join("/")} military active",
        lat: cluster.avg_lat,
        lng: cluster.avg_lng,
        entities: {
          conflict: { name: cluster.conflict_name, events: cluster.event_count.to_i },
          flights: { military: mil_count, callsigns: callsigns.first(5), countries: countries },
        },
        detected_at: Time.current.iso8601,
      }
    end

    insights
  end

  # ── Fires threatening infrastructure ──────────────────────────

  def fire_infrastructure_threats
    # Group fires into clusters
    fire_clusters = FireHotspot.where("acq_datetime > ?", 24.hours.ago)
      .where(confidence: %w[high h nominal n])
      .select("ROUND(CAST(latitude AS numeric), 0) as clat, ROUND(CAST(longitude AS numeric), 0) as clng, COUNT(*) as fire_count, MAX(frp) as max_frp")
      .group("clat, clng")
      .having("COUNT(*) >= 5")

    insights = []
    fire_clusters.each do |cluster|
      bounds = bbox(cluster.clat, cluster.clng, 100)
      plants = PowerPlant.within_bounds(bounds)
      nuclear = plants.where(primary_fuel: "Nuclear")
      next if plants.count == 0

      severity = nuclear.any? ? "critical" : (cluster.fire_count.to_i > 20 ? "high" : "medium")

      insights << {
        type: "fire_infrastructure",
        severity: severity,
        title: "#{cluster.fire_count.to_i} fire hotspots near #{plants.count} power plant#{"s" unless plants.count == 1}",
        description: "Max FRP: #{cluster.max_frp&.round(0)}#{nuclear.any? ? " — NUCLEAR plant at risk" : ""}",
        lat: cluster.clat,
        lng: cluster.clng,
        entities: {
          fires: { count: cluster.fire_count.to_i, max_frp: cluster.max_frp },
          plants: plants.limit(5).map { |p| { name: p.name, fuel: p.primary_fuel, capacity: p.capacity_mw } },
        },
        detected_at: Time.current.iso8601,
      }
    end

    insights
  end

  # ── Cable cuts correlated with internet outages ───────────────

  def cable_outage_correlations
    outages = InternetOutage.where("started_at > ? AND level IN (?)", 24.hours.ago, %w[critical major])
    return [] if outages.empty?

    insights = []
    recent_quakes = Earthquake.where("event_time > ? AND magnitude >= 5", 48.hours.ago)

    outages.group_by(&:entity_code).each do |code, country_outages|
      # Check if any recent earthquakes are near submarine cable landing points
      next if recent_quakes.empty?

      nearby_quakes = recent_quakes.select do |eq|
        # Rough proximity check
        country_outages.any? { |o| o.entity_type == "country" }
      end

      next if nearby_quakes.empty?

      sample_outage = country_outages.first
      insights << {
        type: "cable_outage",
        severity: "high",
        title: "Internet outage in #{sample_outage.entity_name} — possible cable damage",
        description: "#{country_outages.size} outage event#{"s" unless country_outages.size == 1}, #{nearby_quakes.size} recent M5+ earthquake#{"s" unless nearby_quakes.size == 1} in region",
        lat: nearby_quakes.first.latitude,
        lng: nearby_quakes.first.longitude,
        entities: {
          outages: country_outages.map { |o| { entity: o.entity_name, level: o.level, score: o.score } }.first(3),
          earthquakes: nearby_quakes.map { |q| { title: q.title, magnitude: q.magnitude } }.first(3),
        },
        detected_at: Time.current.iso8601,
      }
    end

    insights
  end

  # ── Helpers ───────────────────────────────────────────────────

  def bbox(lat, lng, radius_km)
    dlat = radius_km / 111.0
    dlng = radius_km / (111.0 * Math.cos(lat.to_f * Math::PI / 180)).abs
    { lamin: lat - dlat, lamax: lat + dlat, lomin: lng - dlng, lomax: lng + dlng }
  end

  def cables_in_bounds(bounds)
    SubmarineCable.all.select do |cable|
      coords = cable.coordinates
      next false unless coords.is_a?(Array)
      flat = coords.first.is_a?(Array) && coords.first.first.is_a?(Array) ? coords.flatten(1) : coords
      flat.any? { |pt| pt.is_a?(Array) && pt.size >= 2 &&
        pt[1] >= bounds[:lamin] && pt[1] <= bounds[:lamax] &&
        pt[0] >= bounds[:lomin] && pt[0] <= bounds[:lomax] }
    end
  end

  def cell_key(lat, lng)
    return nil unless lat && lng
    clat = (lat.to_f / 2.0).floor * 2.0
    clng = (lng.to_f / 2.0).floor * 2.0
    "#{clat},#{clng}"
  end

  def severity_score(severity)
    { "critical" => 4, "high" => 3, "medium" => 2, "low" => 1 }[severity.to_s] || 0
  end
end
