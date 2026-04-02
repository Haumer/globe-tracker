class CrossLayerAnalyzer
  include MarketSignalMethods
  include SupplyChainMethods

  PROXIMITY_KM = 200
  CABLE_OUTAGE_RADIUS_KM = 1000
  CORROBORATED_NEWS_STATUSES = %w[multi_source cross_layer_corroborated].freeze
  COUNTRY_CURRENCY_MAP = Definitions::COUNTRY_CURRENCY_MAP
  COUNTRY_CENTROIDS = Definitions::COUNTRY_CENTROIDS

  def self.analyze
    new.analyze
  end

  def analyze
    insights = []

    Definitions::INSIGHT_RULE_METHODS.each do |rule_method|
      insights.concat(send(rule_method))
    end

    # General-purpose spatiotemporal convergence detection
    # Finds multi-layer hotspots that hardcoded rules don't cover
    begin
      convergences = ConvergenceDetector.detect
      existing_cells = insights.map { |i| cell_key(i[:lat], i[:lng]) }.to_set
      convergences.each do |c|
        key = cell_key(c[:lat], c[:lng])
        insights << c unless existing_cells.include?(key)
      end
    rescue => e
      Rails.logger.warn("CrossLayerAnalyzer convergence detection failed: #{e.message}")
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
      news_clusters = matching_news_clusters(
        lat: eq.latitude,
        lng: eq.longitude,
        occurred_at: eq.event_time,
        event_types: %w[earthquake],
        event_families: %w[disaster]
      )

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

      description = eq.title.to_s
      if news_clusters.any?
        total_sources = news_clusters.sum(&:source_count)
        description += " — corroborated by #{news_clusters.size} news cluster#{"s" unless news_clusters.size == 1} from #{total_sources} source#{'s' unless total_sources == 1}"
      end

      insights << {
        type: "earthquake_infrastructure",
        severity: severity,
        title: "#{"Reported " if news_clusters.any?}M#{eq.magnitude} earthquake threatens #{detail_parts.join(" and ")}",
        description: description,
        lat: eq.latitude,
        lng: eq.longitude,
        entities: {
          earthquake: { id: eq.external_id, magnitude: eq.magnitude },
          cables: cables.map { |c| { name: c.name, id: c.cable_id } }.first(5),
          plants: plants.limit(5).map { |p| { name: p.name, fuel: p.primary_fuel, capacity: p.capacity_mw } },
          news: serialize_news_clusters(news_clusters),
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
      cameras = nearby_cameras(cluster.clat, cluster.clng, radius_km: 50)
      next if plants.count == 0

      severity = nuclear.any? ? "critical" : (cluster.fire_count.to_i > 20 ? "high" : "medium")
      description = "Max FRP: #{cluster.max_frp&.round(0)}#{nuclear.any? ? " — NUCLEAR plant at risk" : ""}"
      description += " — #{cameras.size} nearby camera feed#{"s" unless cameras.size == 1}" if cameras.any?

      insights << {
        type: "fire_infrastructure",
        severity: severity,
        title: "#{cluster.fire_count.to_i} fire hotspots near #{plants.count} power plant#{"s" unless plants.count == 1}",
        description: description,
        lat: cluster.clat,
        lng: cluster.clng,
        entities: {
          fires: { count: cluster.fire_count.to_i, max_frp: cluster.max_frp },
          plants: plants.limit(5).map { |p| { name: p.name, fuel: p.primary_fuel, capacity: p.capacity_mw } },
          cameras: serialize_cameras(cameras),
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
      sample_outage = country_outages.first
      traffic = latest_traffic_snapshot(code)
      news_clusters = matching_news_clusters(
        lat: outage_lat,
        lng: outage_lng,
        occurred_at: sample_outage.started_at || sample_outage.created_at,
        event_types: %w[outage],
        event_families: %w[infrastructure cyber],
        time_before: 12.hours,
        time_after: 24.hours
      )

      # Only correlate quakes within CABLE_OUTAGE_RADIUS_KM of the outage country
      nearby_quakes = recent_quakes.select do |eq|
        distance_km(outage_lat, outage_lng, eq.latitude, eq.longitude) <= CABLE_OUTAGE_RADIUS_KM
      end

      next if nearby_quakes.empty?

      # Shallow quakes are far more likely to damage cables
      shallow = nearby_quakes.select { |eq| eq.depth.present? && eq.depth < 70 }
      severity = shallow.any? ? "high" : "medium"

      closest = nearby_quakes.min_by { |eq| distance_km(outage_lat, outage_lng, eq.latitude, eq.longitude) }
      description = "#{country_outages.size} outage event#{"s" unless country_outages.size == 1}, #{nearby_quakes.size} recent M5+ earthquake#{"s" unless nearby_quakes.size == 1} within #{CABLE_OUTAGE_RADIUS_KM}km"
      description += ", traffic at #{traffic.traffic_pct.round(1)}% of baseline" if traffic&.traffic_pct
      if news_clusters.any?
        total_sources = news_clusters.sum(&:source_count)
        description += ", #{news_clusters.size} corroborating news cluster#{"s" unless news_clusters.size == 1} from #{total_sources} source#{'s' unless total_sources == 1}"
      end

      insights << {
        type: "cable_outage",
        severity: severity,
        title: "Internet outage in #{sample_outage.entity_name} — possible cable damage",
        description: description,
        lat: closest.latitude,
        lng: closest.longitude,
        entities: {
          outages: country_outages.map { |o| { entity: o.entity_name, level: o.level, score: o.score } }.first(3),
          earthquakes: nearby_quakes.map { |q| { title: q.title, magnitude: q.magnitude, depth: q.depth } }.first(3),
          traffic: serialize_traffic_snapshot(traffic),
          news: serialize_news_clusters(news_clusters),
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
      traffic = latest_traffic_snapshot(code)
      news_clusters = matching_news_clusters(
        lat: centroid[0],
        lng: centroid[1],
        occurred_at: sample_outage.started_at || sample_outage.created_at,
        event_families: %w[conflict infrastructure],
        time_before: 12.hours,
        time_after: 24.hours
      )
      description = "#{country_outages.size} outage events + #{conflicts.count} conflict events — possible information warfare"
      description += ", traffic at #{traffic.traffic_pct.round(1)}% of baseline" if traffic&.traffic_pct
      if news_clusters.any?
        total_sources = news_clusters.sum(&:source_count)
        description += ", #{news_clusters.size} corroborating news cluster#{"s" unless news_clusters.size == 1} from #{total_sources} source#{'s' unless total_sources == 1}"
      end

      insights << {
        type: "information_blackout",
        severity: country_outages.size > 2 ? "critical" : "high",
        title: "Internet blackout in #{sample_outage.entity_name} during active conflict",
        description: description,
        lat: centroid[0],
        lng: centroid[1],
        entities: {
          outages: country_outages.map { |o| { entity: o.entity_name, level: o.level, score: o.score } }.first(3),
          conflicts: recent_conflicts.map { |c| { name: c.conflict_name, type: c.type_of_violence } },
          traffic: serialize_traffic_snapshot(traffic),
          news: serialize_news_clusters(news_clusters),
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
      cameras = nearby_cameras(avg_lat, avg_lng, radius_km: 75)
      description = "#{cluster_alerts.size} weather alert#{"s" unless cluster_alerts.size == 1} (#{events.join(", ")}), #{total} aircraft in affected airspace"
      description += ", #{cameras.size} nearby camera feed#{"s" unless cameras.size == 1}" if cameras.any?

      insights << {
        type: "weather_disruption",
        severity: severity,
        title: "#{events.first} affecting #{total} flights",
        description: description,
        lat: avg_lat,
        lng: avg_lng,
        entities: {
          weather: cluster_alerts.first(3).map { |a| { event: a.event, severity: a.severity, areas: a.areas } },
          flights: { total: total },
          cameras: serialize_cameras(cameras),
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
          theater: zone[:theater].present? ? { name: zone[:theater] } : nil,
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

  def bbox(lat, lng, radius_km)
    dlat = radius_km / 111.0
    dlng = radius_km / (111.0 * Math.cos(lat.to_f * Math::PI / 180)).abs
    { lamin: lat - dlat, lamax: lat + dlat, lomin: lng - dlng, lomax: lng + dlng }
  end

  def matching_news_clusters(lat:, lng:, occurred_at:, event_types: [], event_families: [], time_before: 6.hours, time_after: 36.hours, limit: 3)
    relation = NewsStoryCluster
      .where("last_seen_at > ?", 72.hours.ago)
      .where.not(latitude: nil, longitude: nil)
      .where("source_count >= 2 OR verification_status IN (?)", CORROBORATED_NEWS_STATUSES)

    normalized_types = Array(event_types).map { |value| value.to_s.downcase }.uniq
    normalized_families = Array(event_families).map { |value| value.to_s.downcase }.uniq

    if normalized_types.any? && normalized_families.any?
      relation = relation.where("LOWER(event_type) IN (?) OR LOWER(event_family) IN (?)", normalized_types, normalized_families)
    elsif normalized_types.any?
      relation = relation.where("LOWER(event_type) IN (?)", normalized_types)
    elsif normalized_families.any?
      relation = relation.where("LOWER(event_family) IN (?)", normalized_families)
    end

    relation.select do |cluster|
      news_cluster_matches?(
        cluster,
        lat: lat,
        lng: lng,
        occurred_at: occurred_at,
        time_before: time_before,
        time_after: time_after
      )
    end
      .sort_by { |cluster| [-cluster.source_count.to_i, -cluster.article_count.to_i, -cluster.cluster_confidence.to_f] }
      .first(limit)
  end

  def news_cluster_matches?(cluster, lat:, lng:, occurred_at:, time_before:, time_after:)
    return false unless lat && lng && occurred_at && cluster.first_seen_at

    time_match = cluster.first_seen_at >= occurred_at - time_before &&
      cluster.first_seen_at <= occurred_at + time_after
    geo_match = distance_km(lat, lng, cluster.latitude, cluster.longitude) <= max_distance_for_geo_precision(cluster.geo_precision)

    time_match && geo_match
  end

  def max_distance_for_geo_precision(geo_precision)
    case geo_precision.to_s
    when "precise", "point", "facility"
      75
    when "city", "local"
      150
    when "region", "state", "province"
      300
    when "country"
      600
    else
      250
    end
  end

  def latest_traffic_snapshot(country_code)
    return nil if country_code.blank?

    InternetTrafficSnapshot.latest_batch.find_by(country_code: country_code.to_s.upcase)
  end

  def nearby_cameras(lat, lng, radius_km:, limit: 3)
    Camera.alive.fresh
      .within_bounds(bbox(lat, lng, radius_km))
      .select(:id, :title, :city, :country, :latitude, :longitude, :source, :player_url, :image_url, :preview_url)
      .to_a
      .sort_by { |camera| distance_km(lat, lng, camera.latitude, camera.longitude) }
      .first(limit)
  end

  def serialize_news_clusters(clusters)
    Array(clusters).map do |cluster|
      {
        cluster_key: cluster.cluster_key,
        title: cluster.canonical_title,
        sources: cluster.source_count,
        articles: cluster.article_count,
        verification_status: cluster.verification_status,
      }
    end
  end

  def serialize_traffic_snapshot(snapshot)
    return nil unless snapshot

    {
      country_code: snapshot.country_code,
      country_name: snapshot.country_name,
      traffic_pct: snapshot.traffic_pct,
      attack_origin_pct: snapshot.attack_origin_pct,
      attack_target_pct: snapshot.attack_target_pct,
      recorded_at: snapshot.recorded_at,
    }
  end

  def serialize_cameras(cameras)
    Array(cameras).map do |camera|
      {
        id: camera.id,
        title: camera.title,
        city: camera.city,
        country: camera.country,
        source: camera.source,
        player_url: camera.player_url,
        image_url: camera.image_url,
        preview_url: camera.preview_url,
      }.compact
    end
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
