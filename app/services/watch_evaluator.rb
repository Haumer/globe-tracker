class WatchEvaluator
  def self.evaluate(user)
    new(user).evaluate
  end

  def initialize(user)
    @user = user
    @new_alerts = []
  end

  def evaluate
    @user.watches.active.find_each do |watch|
      next unless watch.cooled_down?

      case watch.watch_type
      when "entity" then evaluate_entity(watch)
      when "area"   then evaluate_area(watch)
      when "event"  then evaluate_event(watch)
      end
    end
    @new_alerts
  end

  private

  def evaluate_entity(watch)
    c = watch.conditions.symbolize_keys
    entity_type = c[:entity_type]
    identifier = c[:identifier].to_s
    match = c[:match] || "callsign_glob"

    case entity_type
    when "flight"
      flights = find_flights(identifier, match)
      flights.each do |f|
        create_alert(watch,
          title: "Flight #{f.callsign || f.icao24} detected",
          entity_type: "flight",
          entity_id: f.icao24,
          lat: f.latitude,
          lng: f.longitude,
          details: { callsign: f.callsign, altitude: f.altitude, military: f.military, origin_country: f.origin_country }
        )
      end
    when "ship"
      ships = find_ships(identifier, match)
      ships.each do |s|
        create_alert(watch,
          title: "Ship #{s.name || s.mmsi} detected",
          entity_type: "ship",
          entity_id: s.mmsi,
          lat: s.latitude,
          lng: s.longitude,
          details: { name: s.name, mmsi: s.mmsi, flag: s.flag, speed: s.speed }
        )
      end
    end
  end

  def evaluate_area(watch)
    c = watch.conditions.symbolize_keys
    bounds = c[:bounds] # [south, west, north, east]
    return unless bounds.is_a?(Array) && bounds.size == 4

    entity_types = Array(c[:entity_types])
    filters = (c[:filters] || {}).symbolize_keys
    bounds_hash = { lamin: bounds[0], lomin: bounds[1], lamax: bounds[2], lomax: bounds[3] }
    found = []

    if entity_types.include?("flight")
      scope = Flight.within_bounds(bounds_hash)
      scope = scope.where(military: true) if filters[:military]
      count = scope.count
      found << "#{count} flight#{"s" unless count == 1}" if count > 0
    end

    if entity_types.include?("ship")
      scope = Ship.where(latitude: bounds[0]..bounds[2], longitude: bounds[1]..bounds[3])
      count = scope.count
      found << "#{count} ship#{"s" unless count == 1}" if count > 0
    end

    if found.any?
      center_lat = (bounds[0] + bounds[2]) / 2.0
      center_lng = (bounds[1] + bounds[3]) / 2.0
      create_alert(watch,
        title: "Area watch: #{found.join(", ")}",
        lat: center_lat,
        lng: center_lng,
        details: { bounds: bounds, found: found, filters: filters }
      )
    end
  end

  def evaluate_event(watch)
    c = watch.conditions.symbolize_keys
    event_type = c[:event_type]
    since = watch.last_triggered_at || 24.hours.ago

    case event_type
    when "earthquake"
      min_mag = (c[:min_magnitude] || 5.0).to_f
      scope = Earthquake.where("magnitude >= ? AND event_time > ?", min_mag, since)
      scope = scope.where(origin_country: c[:region]) if c[:region].present?
      scope.limit(5).each do |eq|
        create_alert(watch,
          title: "M#{eq.magnitude} earthquake: #{eq.title}",
          entity_type: "earthquake",
          entity_id: eq.external_id,
          lat: eq.latitude,
          lng: eq.longitude,
          details: { magnitude: eq.magnitude, depth: eq.depth, tsunami: eq.tsunami }
        )
      end
    when "conflict"
      scope = ConflictEvent.where("event_date > ?", since.to_date)
      scope = scope.where(country: c[:region]) if c[:region].present?
      count = scope.count
      if count > 0
        sample = scope.order(event_date: :desc).first
        create_alert(watch,
          title: "#{count} new conflict event#{"s" unless count == 1}",
          entity_type: "conflict",
          entity_id: sample&.id&.to_s,
          lat: sample&.latitude,
          lng: sample&.longitude,
          details: { count: count, sample_event: sample&.event_type }
        )
      end
    end
  end

  def find_flights(identifier, match)
    case match
    when "callsign_glob"
      pattern = identifier.gsub("*", "%")
      Flight.where("callsign ILIKE ?", pattern).limit(10)
    when "callsign_exact"
      Flight.where(callsign: identifier).limit(10)
    when "icao24"
      Flight.where(icao24: identifier).limit(1)
    when "registration"
      Flight.where(registration: identifier).limit(1)
    else
      Flight.none
    end
  end

  def find_ships(identifier, match)
    case match
    when "name_glob"
      pattern = identifier.gsub("*", "%")
      Ship.where("name ILIKE ?", pattern).limit(10)
    when "mmsi"
      Ship.where(mmsi: identifier).limit(1)
    else
      Ship.none
    end
  end

  def create_alert(watch, attrs)
    # Don't create duplicate alerts for the same entity within the cooldown window
    existing = @user.alerts.where(watch: watch)
    existing = existing.where(entity_id: attrs[:entity_id]) if attrs[:entity_id].present?
    existing = existing.where("created_at > ?", watch.cooldown_minutes.minutes.ago)
    return if existing.exists?

    alert = @user.alerts.create!(attrs.merge(watch: watch))
    watch.update_column(:last_triggered_at, Time.current)
    @new_alerts << alert

    # Push via ActionCable
    AlertsChannel.notify(@user, alert)
    AlertsChannel.update_badge(@user)
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn("WatchEvaluator alert creation failed: #{e.message}")
  end
end
