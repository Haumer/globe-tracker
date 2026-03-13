class ConnectionFinder
  PROXIMITY_KM = 200

  def self.find(entity_type:, lat:, lng:, metadata: {})
    new(entity_type, lat.to_f, lng.to_f, metadata).find
  end

  def initialize(entity_type, lat, lng, metadata)
    @type = entity_type
    @lat = lat
    @lng = lng
    @meta = metadata.symbolize_keys
    @verified = []
    @nearby = []
  end

  def find
    send(:"connect_#{@type}") if respond_to?(:"connect_#{@type}", true)
    add_nearby_items
    { verified: @verified, nearby: @nearby }
  end

  private

  # ── Flight connections ──────────────────────────────────────

  def connect_flight
    check_gps_jamming("In GPS jamming zone")

    # Emergency squawk
    if @meta[:squawk].present? && %w[7500 7600 7700].include?(@meta[:squawk])
      labels = { "7500" => "Hijack", "7600" => "Radio failure", "7700" => "General emergency" }
      @verified << {
        type: "emergency",
        icon: "fa-triangle-exclamation",
        color: "#f44336",
        title: "Emergency squawk #{@meta[:squawk]}",
        detail: labels[@meta[:squawk]],
      }
    end
  end

  # ── Ship connections ────────────────────────────────────────

  def connect_ship
    check_gps_jamming("GPS jamming in area")
  end

  # ── Earthquake connections ──────────────────────────────────

  def connect_earthquake
    bounds = bounding_box(PROXIMITY_KM)

    # Submarine cables near earthquake
    cables = SubmarineCable.all.select do |cable|
      coords = cable.coordinates
      next false unless coords.is_a?(Array)
      # GeoJSON coords may be nested: [[[lng,lat],...]] or [[lng,lat],...]
      flat = coords.first.is_a?(Array) && coords.first.first.is_a?(Array) ? coords.flatten(1) : coords
      flat.any? { |pt| pt.is_a?(Array) && pt.size >= 2 &&
        pt[1] >= bounds[:lamin] && pt[1] <= bounds[:lamax] &&
        pt[0] >= bounds[:lomin] && pt[0] <= bounds[:lomax] }
    end

    if cables.any?
      @verified << {
        type: "submarine_cable",
        icon: "fa-network-wired",
        color: "#26c6da",
        title: "#{cables.size} submarine cable#{"s" unless cables.size == 1} in affected area",
        detail: cables.map(&:name).first(5).join(", "),
        items: cables.first(5).map { |c| { name: c.name, cable_id: c.cable_id } },
      }
    end

    # Power plants near earthquake
    plants = PowerPlant.within_bounds(bounds).order(capacity_mw: :desc).limit(10)
    if plants.any?
      total_mw = plants.sum(:capacity_mw).round(0)
      nuclear = plants.where(primary_fuel: "Nuclear")
      @verified << {
        type: "power_plant",
        icon: "fa-bolt",
        color: nuclear.any? ? "#fdd835" : "#ff9800",
        title: "#{plants.size} power plant#{"s" unless plants.size == 1} within #{PROXIMITY_KM}km",
        detail: "#{total_mw.to_i} MW total capacity#{nuclear.any? ? " (#{nuclear.size} nuclear)" : ""}",
        items: plants.first(5).map { |p| { name: p.name, fuel: p.primary_fuel, capacity: p.capacity_mw, lat: p.latitude, lng: p.longitude } },
      }
    end
  end

  # ── Power plant connections ─────────────────────────────────

  def connect_power_plant
    # Recent earthquakes near plant
    bounds = bounding_box(100)
    quakes = Earthquake.within_bounds(bounds)
                       .where("event_time > ?", 7.days.ago)
                       .order(magnitude: :desc).limit(3)
    if quakes.any?
      @verified << {
        type: "earthquake",
        icon: "fa-house-crack",
        color: "#ff7043",
        title: "Recent seismic activity nearby",
        detail: "M#{quakes.first.magnitude} #{quakes.first.title}",
        items: quakes.map { |q| { title: q.title, magnitude: q.magnitude, lat: q.latitude, lng: q.longitude } },
      }
    end
  end

  # ── Conflict connections ────────────────────────────────────

  def connect_conflict
    # Military flights in the area
    bounds = bounding_box(PROXIMITY_KM)
    mil_flights = Flight.within_bounds(bounds).where(military: true)
    if mil_flights.any?
      @verified << {
        type: "flight",
        icon: "fa-jet-fighter",
        color: "#ef5350",
        title: "#{mil_flights.count} military flight#{"s" unless mil_flights.count == 1} in area",
        detail: mil_flights.limit(5).pluck(:callsign).compact.join(", "),
        items: mil_flights.limit(5).map { |f| { callsign: f.callsign, icao24: f.icao24, lat: f.latitude, lng: f.longitude } },
      }
    end
  end

  # ── Fire hotspot connections ───────────────────────────────

  def connect_fire_hotspot
    # Verified: detecting satellite
    satellite_name = @meta[:satellite]
    if satellite_name.present?
      norad_id = FireHotspot::SATELLITE_NORAD[satellite_name]
      if norad_id
        sat = Satellite.find_by(norad_id: norad_id)
        @verified << {
          type: "satellite",
          icon: "fa-satellite",
          color: "#ce93d8",
          title: "Detected by #{satellite_name}",
          detail: "NORAD #{norad_id}#{sat ? " — #{sat.name}" : ""}",
          norad_id: norad_id,
        }
      end
    end

    bounds = bounding_box(PROXIMITY_KM)

    # Nearby power plants at risk
    plants = PowerPlant.within_bounds(bounds).order(capacity_mw: :desc).limit(5)
    if plants.any?
      total_mw = plants.sum(:capacity_mw).round(0)
      nuclear = plants.where(primary_fuel: "Nuclear")
      @verified << {
        type: "power_plant",
        icon: "fa-bolt",
        color: nuclear.any? ? "#fdd835" : "#ff9800",
        title: "#{plants.size} power plant#{"s" unless plants.size == 1} within #{PROXIMITY_KM}km",
        detail: "#{total_mw.to_i} MW capacity#{nuclear.any? ? " (#{nuclear.size} nuclear)" : ""}",
        items: plants.first(5).map { |p| { name: p.name, fuel: p.primary_fuel, capacity: p.capacity_mw, lat: p.latitude, lng: p.longitude } },
      }
    end
  end

  # ── Nearby (proximity-based, secondary) ─────────────────────

  def add_nearby_items
    bounds = bounding_box(PROXIMITY_KM)
    covered = @verified.map { |v| v[:type] }.to_set

    unless covered.include?("conflict") || @type == "conflict"
      conflicts = ConflictEvent.where(latitude: bounds[:lamin]..bounds[:lamax],
                                       longitude: bounds[:lomin]..bounds[:lomax])
                                .where("date_end IS NULL OR date_end >= ?", 90.days.ago)
                                .limit(3)
      if conflicts.any?
        @nearby << {
          type: "conflict",
          icon: "fa-crosshairs",
          color: "#f44336",
          title: "#{conflicts.size} conflict event#{"s" unless conflicts.size == 1} nearby",
          items: conflicts.map { |c| { name: c.conflict_name, lat: c.latitude, lng: c.longitude } },
        }
      end
    end

    unless covered.include?("earthquake") || @type == "earthquake"
      quakes = Earthquake.where(latitude: bounds[:lamin]..bounds[:lamax],
                                 longitude: bounds[:lomin]..bounds[:lomax])
                          .where("event_time > ?", 7.days.ago)
                          .order(magnitude: :desc).limit(3)
      if quakes.any?
        @nearby << {
          type: "earthquake",
          icon: "fa-house-crack",
          color: "#ff7043",
          title: "Recent earthquake#{"s" unless quakes.size == 1} nearby",
          detail: "M#{quakes.first.magnitude} #{quakes.first.title}",
        }
      end
    end

    unless covered.include?("fire_hotspot") || @type == "fire_hotspot"
      fires = FireHotspot.where(latitude: bounds[:lamin]..bounds[:lamax],
                                 longitude: bounds[:lomin]..bounds[:lomax])
                          .where("acq_datetime > ?", 48.hours.ago)
                          .limit(5)
      if fires.any?
        @nearby << {
          type: "fire_hotspot",
          icon: "fa-fire",
          color: "#ff5722",
          title: "#{fires.size} active fire#{"s" unless fires.size == 1} nearby",
        }
      end
    end

    unless covered.include?("flight") || @type == "flight"
      mil = Flight.where(latitude: bounds[:lamin]..bounds[:lamax],
                          longitude: bounds[:lomin]..bounds[:lomax])
                   .where(military: true).count
      if mil > 0
        @nearby << {
          type: "flight",
          icon: "fa-jet-fighter",
          color: "#ef5350",
          title: "#{mil} military flight#{"s" unless mil == 1} in area",
        }
      end
    end
  end

  # ── Shared helpers ──────────────────────────────────────────

  def check_gps_jamming(title)
    jamming = GpsJammingSnapshot.where("recorded_at > ?", 1.hour.ago).where(
      cell_lat: (@lat - 1.5)..(@lat + 1.5),
      cell_lng: (@lng - 1.5)..(@lng + 1.5)
    ).where("percentage > 5").order(percentage: :desc).first

    return unless jamming

    @verified << {
      type: "gps_jamming",
      icon: "fa-satellite-dish",
      color: "#ff9800",
      title: title,
      detail: "#{jamming.percentage.round(1)}% signal degradation (#{jamming.level})",
      lat: jamming.cell_lat,
      lng: jamming.cell_lng,
    }
  end

  def bounding_box(radius_km)
    dlat = radius_km / 111.0
    dlng = radius_km / (111.0 * Math.cos(@lat * Math::PI / 180)).abs
    { lamin: @lat - dlat, lamax: @lat + dlat, lomin: @lng - dlng, lomax: @lng + dlng }
  end
end
