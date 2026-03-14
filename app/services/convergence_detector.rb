# Spatiotemporal convergence detector — finds geographic areas where multiple
# data layers are active simultaneously, producing cross-layer insights that
# go beyond hardcoded correlation rules.
#
# How it works:
#   1. Collect recent "events" from every layer (anything with lat/lng + timestamp)
#   2. Grid the world into cells (2° ≈ 220km at equator)
#   3. Score cells by number of distinct layers + event severity
#   4. Generate human-readable narratives for high-scoring cells
#
# This complements CrossLayerAnalyzer (which has specific, handcrafted rules)
# by automatically discovering interesting convergences you didn't anticipate.

class ConvergenceDetector
  CELL_SIZE = 2.0 # degrees — ~220km at equator
  MIN_LAYERS = 2  # minimum distinct layers to qualify as a convergence
  MIN_SCORE = 10  # minimum score to surface (filters routine overlaps)
  MAX_RESULTS = 10

  LAYER_CONFIGS = {
    earthquake: {
      label: "Earthquakes",
      icon: "fa-house-crack",
      color: "#ff7043",
      query: -> { Earthquake.where("event_time > ?", 24.hours.ago).where.not(latitude: nil) },
      extract: ->(r) { { lat: r.latitude, lng: r.longitude, time: r.event_time,
                          weight: r.magnitude.to_f, detail: "M#{r.magnitude} #{r.title}",
                          id: r.external_id } },
    },
    fire: {
      label: "Fire Hotspots",
      icon: "fa-fire",
      color: "#ff5722",
      query: -> { FireHotspot.where("acq_datetime > ?", 24.hours.ago).where.not(latitude: nil) },
      extract: ->(r) { { lat: r.latitude, lng: r.longitude, time: r.acq_datetime,
                          weight: [(r.frp || 1).to_f / 50, 3].min, detail: "FRP #{r.frp&.round(0)}",
                          id: r.id } },
      aggregate: true, # aggregate by cell rather than listing individual fires
    },
    conflict: {
      label: "Conflict Events",
      icon: "fa-burst",
      color: "#e53935",
      query: -> { ConflictEvent.where("date_start > ? OR date_end > ?", 7.days.ago, 7.days.ago).where.not(latitude: nil) },
      extract: ->(r) { { lat: r.latitude, lng: r.longitude, time: r.date_start,
                          weight: (r.deaths_total || 0) > 10 ? 3 : 1,
                          detail: r.conflict_name || r.side_a,
                          id: r.id } },
    },
    military_flight: {
      label: "Military Flights",
      icon: "fa-jet-fighter",
      color: "#ef5350",
      query: -> { Flight.where(military: true).where.not(latitude: nil) },
      extract: ->(r) { { lat: r.latitude, lng: r.longitude, time: r.updated_at,
                          weight: 1, detail: r.callsign || r.icao24,
                          id: r.icao24 } },
      aggregate: true,
    },
    jamming: {
      label: "GPS Jamming",
      icon: "fa-satellite-dish",
      color: "#ff9800",
      query: -> { GpsJammingSnapshot.where("recorded_at > ? AND percentage > 10", 2.hours.ago) },
      extract: ->(r) { { lat: r.cell_lat, lng: r.cell_lng, time: r.recorded_at,
                          weight: r.percentage.to_f / 25, detail: "#{r.percentage.round(0)}% degradation",
                          id: "#{r.cell_lat},#{r.cell_lng}" } },
    },
    internet_outage: {
      label: "Internet Outages",
      icon: "fa-wifi",
      color: "#ab47bc",
      # Internet outages don't have lat/lng — skip in spatial clustering
      query: -> { InternetOutage.none },
      extract: ->(r) { nil },
    },
    natural_event: {
      label: "Natural Events",
      icon: "fa-tornado",
      color: "#42a5f5",
      query: -> { NaturalEvent.where("updated_at > ?", 48.hours.ago).where.not(latitude: nil) },
      extract: ->(r) { { lat: r.latitude, lng: r.longitude, time: r.updated_at,
                          weight: 2, detail: "#{r.category_title}: #{r.title}",
                          id: r.id } },
    },
    news: {
      label: "News Events",
      icon: "fa-newspaper",
      color: "#78909c",
      query: -> { NewsEvent.where("published_at > ?", 12.hours.ago).where.not(latitude: nil)
                           .where(threat_level: %w[2 3 4 5 high critical warning]) },
      extract: ->(r) { { lat: r.latitude, lng: r.longitude, time: r.published_at,
                          weight: (r.threat_level || 1).to_f / 2, detail: r.title&.truncate(80),
                          id: r.id } },
      aggregate: true,
    },
    nuclear_plant: {
      label: "Nuclear Plants",
      icon: "fa-radiation",
      color: "#fdd835",
      query: -> { PowerPlant.where(primary_fuel: "Nuclear") },
      extract: ->(r) { { lat: r.latitude, lng: r.longitude, time: nil,
                          weight: 3, detail: "#{r.name} (#{r.capacity_mw}MW)",
                          id: r.id } },
      static: true, # always present — only interesting when other layers converge
    },
    submarine_cable: {
      label: "Submarine Cables",
      icon: "fa-network-wired",
      color: "#26a69a",
      # Cables are lines, not points — handled specially via landing points
      query: -> { SubmarineCable.none },
      extract: ->(r) { nil },
    },
  }.freeze

  def self.detect
    Rails.cache.fetch("convergence_insights", expires_in: 3.minutes) do
      new.detect
    end
  end

  def detect
    # 1. Collect events from all layers into cells
    cells = Hash.new { |h, k| h[k] = { layers: Hash.new { |h2, k2| h2[k2] = [] }, lat: 0, lng: 0 } }

    LAYER_CONFIGS.each do |layer_key, config|
      records = config[:query].call
      records = records.limit(500) if config[:aggregate]

      records.find_each do |record|
        event = config[:extract].call(record)
        next unless event && event[:lat] && event[:lng]

        cell_key = cell_for(event[:lat], event[:lng])
        cells[cell_key][:layers][layer_key] << event
        cells[cell_key][:lat] = (event[:lat].to_f / CELL_SIZE).round * CELL_SIZE
        cells[cell_key][:lng] = (event[:lng].to_f / CELL_SIZE).round * CELL_SIZE
      end
    end

    # Also inject submarine cable landing points into cells
    inject_cable_landing_points(cells)

    # 2. Filter cells with fewer than MIN_LAYERS distinct non-static layers
    significant_cells = cells.select do |_key, cell|
      dynamic_layers = cell[:layers].keys.reject { |k| LAYER_CONFIGS[k]&.dig(:static) }
      dynamic_layers.size >= MIN_LAYERS
    end

    # 3. Score, filter, and rank
    scored = significant_cells.filter_map do |key, cell|
      score = compute_score(cell)
      next if score < MIN_SCORE
      { key: key, cell: cell, score: score }
    end.sort_by { |s| -s[:score] }.first(MAX_RESULTS)

    # 4. Generate narratives
    scored.map { |s| build_insight(s[:cell], s[:score]) }
  end

  private

  def cell_for(lat, lng)
    clat = (lat.to_f / CELL_SIZE).floor * CELL_SIZE
    clng = (lng.to_f / CELL_SIZE).floor * CELL_SIZE
    "#{clat},#{clng}"
  end

  def inject_cable_landing_points(cells)
    SubmarineCable.find_each do |cable|
      landing = cable.landing_points
      next unless landing.is_a?(Array)

      landing.each do |lp|
        lat = lp["lat"] || lp["latitude"]
        lng = lp["lng"] || lp["longitude"] || lp["lon"]
        next unless lat && lng

        cell_key = cell_for(lat, lng)
        next unless cells.key?(cell_key) # only add cables to cells that already have events

        cells[cell_key][:layers][:submarine_cable] << {
          lat: lat.to_f, lng: lng.to_f, time: nil,
          weight: 2, detail: cable.name, id: cable.cable_id,
        }
      end
    end
  end

  def compute_score(cell)
    layers = cell[:layers]
    dynamic_layers = layers.keys.reject { |k| LAYER_CONFIGS[k]&.dig(:static) }

    # Base score: number of distinct dynamic layers (exponential — 3 layers = 9, 4 = 16, 5 = 25)
    layer_score = dynamic_layers.size ** 2

    # Weight score: sum of max weight per layer (captures severity)
    weight_score = layers.sum { |_k, events| events.map { |e| e[:weight] || 1 }.max }

    # Temporal tightness bonus: if events from different layers happened within 1 hour
    timestamps = layers.values.flatten.filter_map { |e| e[:time] }.sort
    temporal_bonus = 0
    if timestamps.size >= 2
      span_hours = (timestamps.last - timestamps.first).to_f / 3600
      temporal_bonus = span_hours < 1 ? 5 : (span_hours < 6 ? 3 : 1)
    end

    # Nuclear plant multiplier
    nuclear_bonus = layers.key?(:nuclear_plant) ? 3 : 0

    layer_score + weight_score + temporal_bonus + nuclear_bonus
  end

  def build_insight(cell, score)
    layers = cell[:layers]
    lat = cell[:lat]
    lng = cell[:lng]

    # Determine severity from score
    severity = if score >= 30
      "critical"
    elsif score >= 20
      "high"
    elsif score >= 12
      "medium"
    else
      "low"
    end

    # Build narrative title
    layer_labels = layers.keys.map { |k| LAYER_CONFIGS[k][:label] }.compact
    title = "#{layer_labels.size}-layer convergence: #{layer_labels.join(", ")}"

    # Build description from top events per layer
    description_parts = []
    entities = {}

    layers.each do |layer_key, events|
      config = LAYER_CONFIGS[layer_key]
      next unless config

      if config[:aggregate]
        count = events.size
        top = events.max_by { |e| e[:weight] || 0 }
        description_parts << "#{count} #{config[:label].downcase} (#{top[:detail]})"
        entities[layer_key] = { count: count, top: top[:detail] }
      else
        top_events = events.sort_by { |e| -(e[:weight] || 0) }.first(3)
        details = top_events.map { |e| e[:detail] }
        description_parts << "#{config[:label]}: #{details.join("; ")}"
        entities[layer_key] = top_events.map { |e| { detail: e[:detail], id: e[:id] } }
      end
    end

    # Temporal context
    timestamps = layers.values.flatten.filter_map { |e| e[:time] }.sort
    if timestamps.size >= 2
      span = timestamps.last - timestamps.first
      if span < 3600
        description_parts << "All within #{(span / 60).round}min window"
      elsif span < 86400
        description_parts << "Over #{(span / 3600).round}h window"
      end
    end

    {
      type: "convergence",
      severity: severity,
      title: title,
      description: description_parts.join(". "),
      lat: lat,
      lng: lng,
      layer_count: layers.keys.size,
      layers: layers.keys.map(&:to_s),
      entities: entities,
      score: score,
      detected_at: Time.current.iso8601,
    }
  end
end
