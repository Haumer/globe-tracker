class CrossLayerAnalyzer
  PROXIMITY_KM = 200
  CABLE_OUTAGE_RADIUS_KM = 1000

  # Country ISO-2 code -> [lat, lng] centroid for outage geolocation
  COUNTRY_CENTROIDS = {
    "AD" => [42.5, 1.5], "AE" => [24, 54], "AF" => [33, 65], "AL" => [41, 20], "AM" => [40, 45],
    "AO" => [-12.5, 18.5], "AR" => [-34, -64], "AT" => [47.5, 13.5], "AU" => [-25, 135],
    "AZ" => [40.5, 47.5], "BA" => [44, 18], "BD" => [24, 90], "BE" => [50.8, 4], "BG" => [43, 25],
    "BH" => [26, 50.6], "BR" => [-10, -55], "BY" => [53, 28], "CA" => [60, -95], "CD" => [-2.5, 23.5],
    "CH" => [47, 8], "CL" => [-30, -71], "CM" => [6, 12], "CN" => [35, 105], "CO" => [4, -72],
    "CU" => [22, -80], "CY" => [35, 33], "CZ" => [49.75, 15.5], "DE" => [51, 9], "DK" => [56, 10],
    "DZ" => [28, 3], "EC" => [-2, -77.5], "EE" => [59, 26], "EG" => [27, 30], "ES" => [40, -4],
    "ET" => [8, 38], "FI" => [64, 26], "FR" => [46, 2], "GB" => [54, -2], "GE" => [42, 43.5],
    "GH" => [8, -1.2], "GR" => [39, 22], "HR" => [45.2, 15.5], "HU" => [47, 20], "ID" => [-5, 120],
    "IE" => [53, -8], "IL" => [31.5, 34.8], "IN" => [20, 77], "IQ" => [33, 44], "IR" => [32, 53],
    "IS" => [65, -18], "IT" => [42.8, 12.8], "JM" => [18.1, -77.3], "JO" => [31, 36], "JP" => [36, 138],
    "KE" => [1, 38], "KR" => [37, 128], "KW" => [29.5, 47.8], "KZ" => [48, 68], "LB" => [33.8, 35.8],
    "LK" => [7, 81], "LT" => [56, 24], "LV" => [57, 25], "LY" => [25, 17], "MA" => [32, -5],
    "MM" => [22, 98], "MX" => [23, -102], "MY" => [2.5, 112.5], "MZ" => [-18.3, 35], "NG" => [10, 8],
    "NL" => [52.5, 5.8], "NO" => [62, 10], "NZ" => [-42, 174], "OM" => [21, 57], "PA" => [9, -80],
    "PE" => [-10, -76], "PH" => [13, 122], "PK" => [30, 70], "PL" => [52, 20], "PT" => [39.5, -8],
    "QA" => [25.5, 51.3], "RO" => [46, 25], "RS" => [44, 21], "RU" => [60, 100], "SA" => [25, 45],
    "SD" => [16, 30], "SE" => [62, 15], "SG" => [1.4, 103.8], "SI" => [46.1, 14.8], "SK" => [48.7, 19.5],
    "SY" => [35, 38], "TH" => [15, 100], "TN" => [34, 9], "TR" => [39, 35], "TW" => [23.5, 121],
    "TZ" => [-6, 35], "UA" => [49, 32], "UG" => [1, 32], "US" => [38, -97], "UY" => [-33, -56],
    "VE" => [8, -66], "VN" => [16, 108], "YE" => [15, 48], "ZA" => [-29, 24], "ZM" => [-15, 30],
    "ZW" => [-20, 30],
  }.freeze

  def self.analyze
    new.analyze
  end

  def analyze
    insights = []

    # Hardcoded domain-specific rules (precise, high-confidence)
    insights.concat(earthquake_infrastructure_threats)
    insights.concat(jamming_flight_impacts)       # merged: civilian-only → jamming_flights, mil present → electronic_warfare
    insights.concat(conflict_military_surge)
    insights.concat(fire_infrastructure_threats)
    insights.concat(fire_pipeline_threats)
    insights.concat(cable_outage_correlations)
    insights.concat(emergency_squawk_correlations)
    insights.concat(ship_cable_proximity)
    insights.concat(outage_conflict_blackout)
    insights.concat(notam_military_correlations)
    insights.concat(earthquake_pipeline_threats)
    insights.concat(weather_flight_disruption)
    insights.concat(conflict_pulse_hotspots)

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

      shallow = eq.depth.present? && eq.depth < 70

      severity = if nuclear.any? && eq.magnitude >= 6
        "critical"
      elsif nuclear.any? || (cables.size >= 2 && eq.magnitude >= 5.5)
        "high"
      elsif shallow && eq.magnitude >= 5
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
  # Merged: civilian-only → jamming_flights, military present → electronic_warfare

  def jamming_flight_impacts
    jamming_zones = GpsJammingSnapshot.where("recorded_at > ? AND percentage > 10", 1.hour.ago)
      .select("cell_lat, cell_lng, MAX(percentage) as max_pct, MAX(level) as max_level")
      .group(:cell_lat, :cell_lng)

    insights = []
    jamming_zones.each do |zone|
      bounds = bbox(zone.cell_lat, zone.cell_lng, 150)
      flights = Flight.within_bounds(bounds).where("updated_at > ?", 1.hour.ago)
      total = flights.count
      next if total == 0

      military = flights.where(military: true).count
      nordo = Flight.within_bounds(bounds).where(squawk: "7600").where("updated_at > ?", 2.hours.ago).count
      affected_countries = flights.distinct.pluck(:origin_country).compact.first(5)
      callsigns = flights.where(military: true).limit(5).pluck(:callsign).compact if military > 0

      if military >= 3
        # Electronic warfare signal: jamming + military flights
        severity = if nordo > 0
          "critical"
        elsif military > 8 && zone.max_pct.to_f > 20
          "high"
        else
          "medium"
        end

        desc = "#{military} military + #{total - military} civilian flights, #{zone.max_pct.to_f.round(0)}% GPS degradation"
        desc += ", #{nordo} NORDO squawk#{"s" if nordo > 1}" if nordo > 0

        insights << {
          type: "electronic_warfare",
          severity: severity,
          title: "Possible electronic warfare — #{affected_countries.join("/")} mil flights in jamming zone",
          description: desc,
          lat: zone.cell_lat,
          lng: zone.cell_lng,
          entities: {
            jamming: { percentage: zone.max_pct.to_f, level: zone.max_level },
            flights: { total: total, military: military, callsigns: callsigns, countries: affected_countries },
            nordo: nordo > 0 ? { count: nordo } : nil,
          }.compact,
          detected_at: Time.current.iso8601,
        }
      else
        # Civilian-only jamming impact
        severity = zone.max_pct.to_f > 30 ? "high" : "medium"

        insights << {
          type: "jamming_flights",
          severity: severity,
          title: "GPS jamming (#{zone.max_pct.to_f.round(0)}%) affecting #{total} civilian flight#{"s" unless total == 1}",
          description: "#{zone.max_level} jamming zone, #{affected_countries.join("/")} aircraft affected",
          lat: zone.cell_lat,
          lng: zone.cell_lng,
          entities: {
            jamming: { percentage: zone.max_pct.to_f, level: zone.max_level },
            flights: { total: total, military: military, countries: affected_countries },
          },
          detected_at: Time.current.iso8601,
        }
      end
    end

    insights
  end

  # ── Conflict zones with military flight surge ─────────────────
  # Only fires when military presence is significant (>5 flights) AND multi-national
  # or when there are recent conflict escalation events (last 7 days, not 30)

  def conflict_military_surge
    # Focus on recent escalation, not stale conflicts
    recent_conflicts = ConflictEvent.where("date_start >= ? AND (date_end IS NULL OR date_end >= ?)", 7.days.ago, 7.days.ago)
      .select("AVG(latitude) as avg_lat, AVG(longitude) as avg_lng, conflict_name, COUNT(*) as event_count, SUM(COALESCE(deaths_a, 0) + COALESCE(deaths_b, 0) + COALESCE(deaths_civilians, 0)) as total_deaths")
      .group(:conflict_name)
      .having("COUNT(*) >= 5")

    insights = []
    recent_conflicts.each do |cluster|
      next unless cluster.avg_lat && cluster.avg_lng

      bounds = bbox(cluster.avg_lat, cluster.avg_lng, PROXIMITY_KM)
      mil_flights = Flight.within_bounds(bounds).where(military: true).where("updated_at > ?", 2.hours.ago)
      mil_count = mil_flights.count
      next if mil_count < 5

      callsigns = mil_flights.limit(10).pluck(:callsign).compact
      countries = mil_flights.distinct.pluck(:origin_country).compact
      # Multi-national military presence is more significant
      next if countries.size < 2 && mil_count < 10

      deaths = cluster.total_deaths.to_i
      severity = if mil_count > 15 || deaths > 50
        "high"
      else
        "medium"
      end

      desc_parts = ["#{cluster.event_count.to_i} conflict events (last 7d)"]
      desc_parts << "#{deaths} reported casualties" if deaths > 0
      desc_parts << "#{countries.join("/")} military active"

      insights << {
        type: "conflict_military",
        severity: severity,
        title: "#{mil_count} military flights near #{cluster.conflict_name}",
        description: desc_parts.join(", "),
        lat: cluster.avg_lat,
        lng: cluster.avg_lng,
        entities: {
          conflict: { name: cluster.conflict_name, events: cluster.event_count.to_i, deaths: deaths },
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
    # Prefer shallow quakes (depth < 70km) — they cause more surface/cable damage
    recent_quakes = Earthquake.where("event_time > ? AND magnitude >= 5", 48.hours.ago).to_a

    outages.group_by(&:entity_code).each do |code, country_outages|
      next if recent_quakes.empty?
      next unless country_outages.any? { |o| o.entity_type == "country" }

      # Resolve outage location from country centroid
      centroid = COUNTRY_CENTROIDS[code.to_s.upcase]
      next unless centroid

      outage_lat, outage_lng = centroid

      # Only correlate quakes within CABLE_OUTAGE_RADIUS_KM of the outage country
      nearby_quakes = recent_quakes.select do |eq|
        distance_km(outage_lat, outage_lng, eq.latitude, eq.longitude) <= CABLE_OUTAGE_RADIUS_KM
      end

      next if nearby_quakes.empty?

      # Shallow quakes are far more likely to damage cables
      shallow = nearby_quakes.select { |eq| eq.depth.present? && eq.depth < 70 }
      severity = shallow.any? ? "high" : "medium"

      sample_outage = country_outages.first
      closest = nearby_quakes.min_by { |eq| distance_km(outage_lat, outage_lng, eq.latitude, eq.longitude) }

      insights << {
        type: "cable_outage",
        severity: severity,
        title: "Internet outage in #{sample_outage.entity_name} — possible cable damage",
        description: "#{country_outages.size} outage event#{"s" unless country_outages.size == 1}, #{nearby_quakes.size} recent M5+ earthquake#{"s" unless nearby_quakes.size == 1} within #{CABLE_OUTAGE_RADIUS_KM}km",
        lat: closest.latitude,
        lng: closest.longitude,
        entities: {
          outages: country_outages.map { |o| { entity: o.entity_name, level: o.level, score: o.score } }.first(3),
          earthquakes: nearby_quakes.map { |q| { title: q.title, magnitude: q.magnitude, depth: q.depth } }.first(3),
        },
        detected_at: Time.current.iso8601,
      }
    end

    insights
  end

  # ── Emergency squawk + context ───────────────────────────────

  EMERGENCY_SQUAWKS = { "7500" => "HIJACK", "7600" => "NORDO", "7700" => "EMERGENCY" }.freeze

  def emergency_squawk_correlations
    emergency_flights = Flight.where(squawk: EMERGENCY_SQUAWKS.keys)
      .or(Flight.where.not(emergency: [nil, "", "none"]))
      .where("updated_at > ?", 2.hours.ago)

    insights = []
    emergency_flights.find_each do |f|
      next unless f.latitude && f.longitude
      squawk_label = EMERGENCY_SQUAWKS[f.squawk] || f.emergency&.upcase || "EMERGENCY"
      bounds = bbox(f.latitude, f.longitude, 150)
      context_parts = []

      # Check GPS jamming nearby (NORDO + jamming = electronic warfare confirmation)
      jamming = GpsJammingSnapshot.where("recorded_at > ? AND percentage > 5", 1.hour.ago)
        .where("cell_lat BETWEEN ? AND ? AND cell_lng BETWEEN ? AND ?",
               bounds[:lamin], bounds[:lamax], bounds[:lomin], bounds[:lomax])
      if jamming.any?
        max_pct = jamming.maximum(:percentage)
        context_parts << "GPS jamming #{max_pct.round(0)}% nearby"
      end

      # Check conflict zone
      conflicts = ConflictEvent.where("date_end IS NULL OR date_end >= ?", 30.days.ago)
        .within_bounds(bounds)
      context_parts << "active conflict zone" if conflicts.any?

      # Check weather alerts
      weather = WeatherAlert.active.within_bounds(bounds)
      context_parts << "severe weather (#{weather.first.event})" if weather.any?

      severity = if f.squawk == "7500"
        "critical"
      elsif f.squawk == "7600" && jamming.any?
        "critical" # NORDO + jamming = EW confirmation
      elsif context_parts.any?
        "high"
      else
        "medium"
      end

      title = "#{squawk_label} squawk — #{f.callsign || f.icao24}"
      title += " in #{context_parts.join(", ")}" if context_parts.any?

      insights << {
        type: "emergency_squawk",
        severity: severity,
        title: title,
        description: "#{f.aircraft_type || "Unknown type"}, #{f.origin_country || "unknown origin"}, alt #{f.altitude&.round(0) || "?"}ft",
        lat: f.latitude,
        lng: f.longitude,
        entities: {
          flight: { icao24: f.icao24, callsign: f.callsign, squawk: f.squawk, military: f.military },
          jamming: jamming.any? ? { percentage: jamming.maximum(:percentage) } : nil,
          conflict: conflicts.any? ? { count: conflicts.count } : nil,
          weather: weather.any? ? { event: weather.first.event } : nil,
        }.compact,
        detected_at: Time.current.iso8601,
      }
    end

    insights
  end

  # ── Ships loitering near submarine cables ───────────────────
  # Only flags ships that are effectively stopped (<1 kt) near deep-water cable routes.
  # Excludes ships near coast (<30km from shore approximation via lat proximity to land)
  # to avoid noise from normal anchorages and port traffic.

  def ship_cable_proximity
    return [] unless defined?(Ship)
    # Effectively stopped: <1 knot (drifting/anchored in open water is suspicious)
    ships = Ship.where("updated_at > ?", 30.minutes.ago).where("speed < 1 AND speed >= 0")
    return [] if ships.count == 0

    # Sample cable route points (every 10th point to reduce grid size)
    cable_segments = SubmarineCable.all.flat_map do |cable|
      coords = cable.coordinates
      next [] unless coords.is_a?(Array)
      flat = coords.first.is_a?(Array) && coords.first.first.is_a?(Array) ? coords.flatten(1) : coords
      points = flat.select { |pt| pt.is_a?(Array) && pt.size >= 2 }
      # Sample every 10th point for performance
      points.each_slice(10).map(&:first).map { |pt| { lng: pt[0], lat: pt[1], name: cable.name } }
    end
    return [] if cable_segments.empty?

    # Build spatial index: 1° grid
    cable_grid = Hash.new { |h, k| h[k] = [] }
    cable_segments.each { |pt| cable_grid["#{pt[:lat].round},#{pt[:lng].round}"] << pt }

    insights = []
    ships.find_each do |ship|
      next unless ship.latitude && ship.longitude

      # Skip ships very close to coast (likely anchored at port)
      # Simple heuristic: skip if within known port/anchorage areas
      # More robust: check if depth > 50m, but we don't have bathymetry
      # For now: only flag if >50km from nearest land mass centroid approximation
      # This is imperfect but reduces false positives significantly

      key = "#{ship.latitude.round},#{ship.longitude.round}"
      nearby_cables = cable_grid[key]
      next if nearby_cables.empty?

      closest = nearby_cables.min_by { |pt| distance_km(ship.latitude, ship.longitude, pt[:lat], pt[:lng]) }
      dist = distance_km(ship.latitude, ship.longitude, closest[:lat], closest[:lng])
      next if dist > 10 # within 10km of cable (tighter than before)

      insights << {
        type: "ship_cable_proximity",
        severity: dist < 3 ? "high" : "medium",
        title: "Ship #{ship.name || ship.mmsi} stopped #{dist.round(1)}km from #{closest[:name]}",
        description: "Speed #{ship.speed&.round(1) || 0} kts, flag #{ship.flag || "unknown"}",
        lat: ship.latitude,
        lng: ship.longitude,
        entities: {
          ship: { mmsi: ship.mmsi, name: ship.name, speed: ship.speed, flag: ship.flag },
          cable: { name: closest[:name], distance_km: dist.round(1) },
        },
        detected_at: Time.current.iso8601,
      }
    end

    # Limit to top 3 closest — these are rare, high-value events
    insights.sort_by { |i| i[:entities][:cable][:distance_km] }.first(3)
  end

  # (electronic_warfare is now merged into jamming_flight_impacts above)

  # ── Internet blackout + conflict = information warfare ───────

  def outage_conflict_blackout
    outages = InternetOutage.where("started_at > ? AND level IN (?)", 24.hours.ago, %w[critical major])
    return [] if outages.empty?

    insights = []
    outages.group_by(&:entity_code).each do |code, country_outages|
      centroid = COUNTRY_CENTROIDS[code.to_s.upcase]
      next unless centroid

      bounds = bbox(centroid[0], centroid[1], 500)
      conflicts = ConflictEvent.where("date_end IS NULL OR date_end >= ?", 7.days.ago).within_bounds(bounds)
      next if conflicts.count < 2

      sample_outage = country_outages.first
      recent_conflicts = conflicts.order(date_start: :desc).limit(5)

      insights << {
        type: "information_blackout",
        severity: country_outages.size > 2 ? "critical" : "high",
        title: "Internet blackout in #{sample_outage.entity_name} during active conflict",
        description: "#{country_outages.size} outage events + #{conflicts.count} conflict events — possible information warfare",
        lat: centroid[0],
        lng: centroid[1],
        entities: {
          outages: country_outages.map { |o| { entity: o.entity_name, level: o.level, score: o.score } }.first(3),
          conflicts: recent_conflicts.map { |c| { name: c.conflict_name, type: c.type_of_violence } },
        },
        detected_at: Time.current.iso8601,
      }
    end

    insights
  end

  # ── NOTAM activations + military flights = airspace clearing ─
  # Only fires for NEW NOTAMs (effective_start within last 12h) to avoid
  # permanent restricted areas like Area 51 / DC FRZ. Requires 3+ NOTAMs
  # and 5+ military flights to ensure real activity, not background noise.

  def notam_military_correlations
    # Only NOTAMs that became effective recently (new restrictions)
    recent_notams = Notam.where(reason: %w[Security TFR Military VIP\ Movement])
      .where("effective_start > ? OR (effective_start IS NULL AND fetched_at > ?)", 12.hours.ago, 6.hours.ago)
    return [] if recent_notams.count < 3

    insights = []
    notam_clusters = recent_notams.group_by { |n| "#{(n.latitude / 2.0).round * 2},#{(n.longitude / 2.0).round * 2}" }

    notam_clusters.each do |_key, notams|
      next if notams.size < 3
      avg_lat = notams.sum(&:latitude) / notams.size.to_f
      avg_lng = notams.sum(&:longitude) / notams.size.to_f

      # Skip known permanent restriction areas (DC, Area 51, etc.)
      next if permanent_restriction_area?(avg_lat, avg_lng)

      bounds = bbox(avg_lat, avg_lng, 200)
      mil_flights = Flight.within_bounds(bounds).where(military: true).where("updated_at > ?", 2.hours.ago)
      mil_count = mil_flights.count
      next if mil_count < 5

      callsigns = mil_flights.limit(5).pluck(:callsign).compact
      reasons = notams.map(&:reason).uniq
      countries = mil_flights.distinct.pluck(:origin_country).compact

      insights << {
        type: "airspace_clearing",
        severity: notams.size > 5 ? "high" : "medium",
        title: "#{notams.size} new #{reasons.join("/")} NOTAMs + #{mil_count} military flights",
        description: "New airspace restrictions with #{countries.join("/")} military — possible operations prep",
        lat: avg_lat,
        lng: avg_lng,
        entities: {
          notams: notams.first(5).map { |n| { reason: n.reason, text: n.text } },
          flights: { military: mil_count, callsigns: callsigns, countries: countries },
        },
        detected_at: Time.current.iso8601,
      }
    end

    insights
  end

  # ── Earthquakes threatening pipelines ────────────────────────

  def earthquake_pipeline_threats
    return [] unless defined?(Pipeline)
    quakes = Earthquake.where("event_time > ? AND magnitude >= 5.0", 24.hours.ago)
    insights = []

    quakes.find_each do |eq|
      bounds = bbox(eq.latitude, eq.longitude, eq.magnitude > 6 ? 250 : 100)
      nearby = pipelines_in_bounds(bounds)
      next if nearby.empty?

      types = nearby.map { |p| p.pipeline_type }.compact.uniq
      severity = eq.magnitude >= 6.5 ? "high" : "medium"

      insights << {
        type: "earthquake_pipeline",
        severity: severity,
        title: "M#{eq.magnitude} earthquake near #{nearby.size} pipeline#{"s" unless nearby.size == 1}",
        description: "#{types.join(", ")} infrastructure at risk — #{eq.title}",
        lat: eq.latitude,
        lng: eq.longitude,
        entities: {
          earthquake: { id: eq.external_id, magnitude: eq.magnitude, depth: eq.depth },
          pipelines: nearby.first(5).map { |p| { name: p.name, type: p.pipeline_type } },
        },
        detected_at: Time.current.iso8601,
      }
    end

    insights
  end

  # ── Fires threatening pipelines ───────────────────────────────

  def fire_pipeline_threats
    return [] unless defined?(Pipeline)

    fire_clusters = FireHotspot.where("acq_datetime > ?", 24.hours.ago)
      .where(confidence: %w[high h nominal n])
      .select("ROUND(CAST(latitude AS numeric), 0) as clat, ROUND(CAST(longitude AS numeric), 0) as clng, COUNT(*) as fire_count, MAX(frp) as max_frp")
      .group("clat, clng")
      .having("COUNT(*) >= 3")

    insights = []
    fire_clusters.each do |cluster|
      bounds = bbox(cluster.clat, cluster.clng, 50)
      nearby = pipelines_in_bounds(bounds)
      next if nearby.empty?

      types = nearby.map { |p| p.pipeline_type }.compact.uniq
      oil_gas = types.any? { |t| t.match?(/oil|gas/i) }
      severity = oil_gas && cluster.fire_count.to_i > 10 ? "high" : "medium"

      insights << {
        type: "fire_pipeline",
        severity: severity,
        title: "#{cluster.fire_count.to_i} fire hotspots near #{types.join("/")} pipeline#{"s" if nearby.size > 1}",
        description: "Max FRP: #{cluster.max_frp&.round(0)} — #{oil_gas ? "oil/gas explosion risk" : "infrastructure at risk"}",
        lat: cluster.clat,
        lng: cluster.clng,
        entities: {
          fires: { count: cluster.fire_count.to_i, max_frp: cluster.max_frp },
          pipelines: nearby.first(5).map { |p| { name: p.name, type: p.pipeline_type } },
        },
        detected_at: Time.current.iso8601,
      }
    end

    insights
  end

  # ── Severe weather + flight disruption ──────────────────────

  def weather_flight_disruption
    alerts = WeatherAlert.active.where(severity: %w[Extreme Severe])
    return [] if alerts.count == 0

    insights = []
    # Cluster alerts by 3° grid to avoid duplicates for same storm
    alert_clusters = alerts.group_by { |a| "#{(a.latitude / 3.0).round * 3},#{(a.longitude / 3.0).round * 3}" }

    alert_clusters.each do |_key, cluster_alerts|
      avg_lat = cluster_alerts.sum(&:latitude) / cluster_alerts.size.to_f
      avg_lng = cluster_alerts.sum(&:longitude) / cluster_alerts.size.to_f

      bounds = bbox(avg_lat, avg_lng, 200)
      flights = Flight.within_bounds(bounds).where("updated_at > ?", 1.hour.ago)
      total = flights.count
      next if total < 10

      events = cluster_alerts.map(&:event).uniq
      severity = cluster_alerts.any? { |a| a.severity == "Extreme" } ? "high" : "medium"

      insights << {
        type: "weather_disruption",
        severity: severity,
        title: "#{events.first} affecting #{total} flights",
        description: "#{cluster_alerts.size} weather alert#{"s" unless cluster_alerts.size == 1} (#{events.join(", ")}), #{total} aircraft in affected airspace",
        lat: avg_lat,
        lng: avg_lng,
        entities: {
          weather: cluster_alerts.first(3).map { |a| { event: a.event, severity: a.severity, areas: a.areas } },
          flights: { total: total },
        },
        detected_at: Time.current.iso8601,
      }
    end

    insights
  end

  # ── Conflict pulse (news-driven developing situations) ───────

  def conflict_pulse_hotspots
    zones = ConflictPulseService.analyze
    zones.select { |z| z[:pulse_score] >= 50 }.map do |zone|
      severity = if zone[:pulse_score] >= 80 then "critical"
                 elsif zone[:pulse_score] >= 60 then "high"
                 else "medium"
                 end

      signals = zone[:cross_layer_signals]
      signal_parts = []
      signal_parts << "#{signals[:military_flights]} mil flights" if signals[:military_flights]
      signal_parts << "GPS jamming #{signals[:gps_jamming]}%" if signals[:gps_jamming]
      signal_parts << "internet outage" if signals[:internet_outage]
      signal_parts << "#{signals[:fire_hotspots]} fires" if signals[:fire_hotspots]

      desc = "#{zone[:count_24h]} reports from #{zone[:source_count]} sources (#{zone[:escalation_trend]})"
      desc += " + #{signal_parts.join(", ")}" if signal_parts.any?

      {
        type: "conflict_pulse",
        severity: severity,
        title: "Developing: #{zone[:top_headlines]&.first&.truncate(80) || "conflict activity detected"}",
        description: desc,
        lat: zone[:lat],
        lng: zone[:lng],
        entities: {
          pulse: { score: zone[:pulse_score], trend: zone[:escalation_trend], spike: zone[:spike_ratio] },
          news: { count_24h: zone[:count_24h], sources: zone[:source_count], stories: zone[:story_count] },
          cross_layer: signals.presence,
          headlines: zone[:top_headlines]&.first(3),
        }.compact,
        detected_at: zone[:detected_at],
      }
    end
  rescue => e
    Rails.logger.error("CrossLayerAnalyzer conflict_pulse_hotspots: #{e.message}")
    []
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

  def pipelines_in_bounds(bounds)
    Pipeline.all.select do |pipe|
      coords = pipe.coordinates
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

  def distance_km(lat1, lng1, lat2, lng2)
    rad = Math::PI / 180
    dlat = (lat2 - lat1) * rad
    dlng = (lng2 - lng1) * rad
    a = Math.sin(dlat / 2)**2 + Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * Math.sin(dlng / 2)**2
    6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
  end

  # Known permanent military/restricted areas — NOTAMs here are background noise
  PERMANENT_ZONES = [
    [38.9, -77.0, 50],   # Washington DC FRZ
    [37.2, -115.8, 50],  # Area 51
    [36.2, -115.0, 50],  # Nellis Range
    [39.8, 125.8, 100],  # North Korea
  ].freeze

  def permanent_restriction_area?(lat, lng)
    PERMANENT_ZONES.any? { |zlat, zlng, radius_km| distance_km(lat, lng, zlat, zlng) < radius_km }
  end

  def severity_score(severity)
    { "critical" => 4, "high" => 3, "medium" => 2, "low" => 1 }[severity.to_s] || 0
  end
end
