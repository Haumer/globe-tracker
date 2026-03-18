class ConflictPulseService
  CACHE_KEY = "conflict_pulse_zones".freeze
  CELL_SIZE = 2.0
  CONFLICT_CATEGORIES = %w[conflict terror unrest].freeze
  MIN_ARTICLES = 3
  MIN_SOURCES = 2      # require multi-source confirmation
  MIN_TONE = 1.5       # filter out low-intensity articles (|tone| < 1.5)
  MIN_PULSE_SCORE = 20
  MAX_RESULTS = 25

  # Source credibility weights — tier 1 wire services count 3x more than a blog
  TIER_WEIGHTS = { 1 => 3.0, 2 => 2.0, 3 => 1.0, 4 => 0.5 }.freeze
  DEFAULT_WEIGHT = 1.0

  # High-propaganda sources get discounted further
  HIGH_RISK_DISCOUNT = 0.3

  # Situation names — map cell regions to human-readable labels (checked first, most specific)
  SITUATION_NAMES = {
    "Israel-Palestine" => { lat: 30..33, lng: 34..36 },
    "Iran Theater" => { lat: 34..37, lng: 50..54 },
    "Lebanon-Israel Border" => { lat: 33..35, lng: 35..36 },
    "Eastern Ukraine Front" => { lat: 48..52, lng: 34..40 },
    "Kyiv Region" => { lat: 50..52, lng: 29..32 },
    "Moscow / Western Russia" => { lat: 54..57, lng: 36..40 },
    "Iraq Theater" => { lat: 32..35, lng: 43..46 },
    "Gaza Strip" => { lat: 30..32, lng: 34..35 },
    "Strait of Hormuz" => { lat: 26..28, lng: 56..58 },
    "Red Sea / Bab el-Mandeb" => { lat: 12..16, lng: 42..46 },
    "Gulf States" => { lat: 23..26, lng: 46..56 },
    "Sudan / Khartoum" => { lat: 14..17, lng: 31..34 },
    "Turkey" => { lat: 37..42, lng: 28..44 },
    "Iran Region" => { lat: 27..30, lng: 47..55 },
    "Kuwait" => { lat: 28..30, lng: 46..49 },
    "Eastern Mediterranean" => { lat: 34..38, lng: 22..28 },
    "Pakistan-Afghanistan" => { lat: 32..36, lng: 68..74 },
    "Myanmar Region" => { lat: 10..22, lng: 94..102 },
    "Cuba" => { lat: 22..24, lng: -84..-82 },
    "Washington DC" => { lat: 38..40, lng: -78..-76 },
    "Taiwan Strait" => { lat: 23..26, lng: 118..122 },
    "Korean Peninsula" => { lat: 37..40, lng: 125..128 },
  }.freeze

  # Country/region bounds — broad fallback when SITUATION_NAMES doesn't match
  COUNTRY_BOUNDS = {
    "Ukraine" => { lat: 44..53, lng: 22..41 },
    "Russia" => { lat: 41..82, lng: 19..180 },
    "Syria" => { lat: 32..37, lng: 35..42 },
    "Yemen" => { lat: 12..19, lng: 42..54 },
    "Libya" => { lat: 19..34, lng: 9..25 },
    "Somalia" => { lat: -2..12, lng: 41..51 },
    "Ethiopia" => { lat: 3..15, lng: 33..48 },
    "Nigeria" => { lat: 4..14, lng: 3..15 },
    "Mali" => { lat: 10..25, lng: -12..4 },
    "DR Congo" => { lat: -14..6, lng: 12..32 },
    "Mozambique" => { lat: -27..-10, lng: 30..41 },
    "South Sudan" => { lat: 3..13, lng: 24..36 },
    "Central African Republic" => { lat: 2..11, lng: 14..28 },
    "Burkina Faso" => { lat: 9..15, lng: -6..3 },
    "Niger" => { lat: 11..24, lng: 0..16 },
    "Chad" => { lat: 7..24, lng: 13..24 },
    "Cameroon" => { lat: 2..13, lng: 8..17 },
    "Egypt" => { lat: 22..32, lng: 25..37 },
    "Saudi Arabia" => { lat: 16..33, lng: 34..56 },
    "Jordan" => { lat: 29..34, lng: 35..39 },
    "Afghanistan" => { lat: 29..39, lng: 60..75 },
    "Pakistan" => { lat: 24..37, lng: 61..78 },
    "India" => { lat: 6..36, lng: 68..98 },
    "China" => { lat: 18..54, lng: 73..135 },
    "North Korea" => { lat: 37..43, lng: 124..131 },
    "South Korea" => { lat: 33..39, lng: 124..130 },
    "Japan" => { lat: 24..46, lng: 123..146 },
    "Philippines" => { lat: 5..21, lng: 117..127 },
    "Indonesia" => { lat: -11..6, lng: 95..141 },
    "Thailand" => { lat: 5..21, lng: 97..106 },
    "Vietnam" => { lat: 8..24, lng: 102..110 },
    "Mexico" => { lat: 14..33, lng: -118..-86 },
    "Colombia" => { lat: -5..13, lng: -80..-67 },
    "Venezuela" => { lat: 1..13, lng: -73..-60 },
    "Brazil" => { lat: -34..6, lng: -74..-35 },
    "United States" => { lat: 24..50, lng: -125..-66 },
    "Canada" => { lat: 41..84, lng: -141..-52 },
    "United Kingdom" => { lat: 49..61, lng: -9..2 },
    "France" => { lat: 41..52, lng: -5..10 },
    "Germany" => { lat: 47..55, lng: 6..15 },
    "Poland" => { lat: 49..55, lng: 14..25 },
    "Romania" => { lat: 43..49, lng: 20..30 },
    "Spain" => { lat: 36..44, lng: -10..4 },
    "Italy" => { lat: 36..47, lng: 6..19 },
    "Greece" => { lat: 34..42, lng: 19..30 },
    "Algeria" => { lat: 19..37, lng: -9..12 },
    "Tunisia" => { lat: 30..38, lng: 7..12 },
    "Morocco" => { lat: 27..36, lng: -13..-1 },
    "South Africa" => { lat: -35..-22, lng: 16..33 },
    "Kenya" => { lat: -5..5, lng: 34..42 },
    "Tanzania" => { lat: -12..-1, lng: 29..41 },
    "Angola" => { lat: -18..-4, lng: 12..24 },
    "Australia" => { lat: -44..-10, lng: 113..154 },
    "Argentina" => { lat: -56..-21, lng: -74..-53 },
    "Peru" => { lat: -19..0, lng: -82..-68 },
    "Chile" => { lat: -56..-17, lng: -76..-66 },
    "Ecuador" => { lat: -5..2, lng: -81..-75 },
    "Haiti" => { lat: 18..20, lng: -75..-71 },
  }.freeze

  # Theaters — group related situations into broader conflicts
  THEATERS = {
    "Middle East / Iran War" => [
      "Israel-Palestine", "Iran Theater", "Iran Region", "Lebanon-Israel Border",
      "Iraq Theater", "Strait of Hormuz", "Red Sea / Bab el-Mandeb",
      "Gulf States", "Gaza Strip", "Turkey", "Kuwait", "Eastern Mediterranean",
    ],
    "Russia-Ukraine War" => [
      "Eastern Ukraine Front", "Kyiv Region", "Moscow / Western Russia",
    ],
    "Myanmar Civil War" => ["Myanmar", "Myanmar Region"],
    "Afghanistan-Pakistan" => ["Pakistan-Afghanistan"],
  }.freeze

  class << self
    def analyze
      Rails.cache.fetch(CACHE_KEY, expires_in: 10.minutes) { new.compute_full }
    end

    def invalidate
      Rails.cache.delete(CACHE_KEY)
    end
  end

  def compute_full
    zones = compute

    # Assign situation names and theater groupings to zones
    zones.each do |z|
      z[:situation_name] = resolve_situation_name(z)
      z[:theater] = THEATERS.find { |_, situs| situs.include?(z[:situation_name]) }&.first
    end

    # Extract strike arcs from all conflict headlines (last 7 days)
    all_headlines = NewsEvent.where("published_at > ?", 7.days.ago)
      .where(category: CONFLICT_CATEGORIES)
      .where.not(title: [nil, ""])
      .pluck(:title)
    raw_arcs = StrikeArcExtractor.extract(all_headlines)

    # Snap arc endpoints to nearest situation zone so arcs visually connect the bubbles
    strike_arcs = snap_arcs_to_zones(raw_arcs, zones)

    # Build hex cells for theater visualization (lower threshold than zones)
    hex_cells = build_hex_cells

    # Tag each hex cell with its nearest zone
    link_hexes_to_zones(hex_cells, zones)

    # Broadcast surging/escalating zones via ActionCable
    zones.each do |z|
      next unless %w[surging escalating].include?(z[:escalation_trend])
      next unless z[:pulse_score] >= 70
      cache_key = "cpulse_broadcast:#{z[:cell_key]}:#{z[:escalation_trend]}"
      next if Rails.cache.read(cache_key)
      Rails.cache.write(cache_key, true, expires_in: 30.minutes)
      EventsChannel.conflict_escalation(z)
    end

    { zones: zones, strike_arcs: strike_arcs, hex_cells: hex_cells }
  rescue => e
    Rails.logger.error("ConflictPulseService compute_full: #{e.message}")
    { zones: compute, strike_arcs: [], hex_cells: [] }
  end

  def compute
    articles = NewsEvent.where("published_at > ?", 7.days.ago)
      .where.not(latitude: nil, longitude: nil)
      .where(category: CONFLICT_CATEGORIES)
      .select(:id, :title, :url, :name, :latitude, :longitude, :tone, :source, :category,
              :threat_level, :credibility, :story_cluster_id, :published_at)

    # Grid into 2° cells — use headline-detected event location when it differs from article location
    cells = Hash.new { |h, k| h[k] = [] }
    # Obvious non-conflict keywords to filter out miscategorized articles
    noise_patterns = /(oscar|oscara|academy award|grammy|super bowl|world cup|champions league|europa league|\bnba\b|\bnfl\b|\bmlb\b|tennis|golf tournament|cricket match|red carpet|box office|best picture|best actor|best actress|best film)/i

    articles.find_each do |a|
      next if a.tone && a.tone.abs < MIN_TONE
      next if a.title&.match?(noise_patterns)
      # Check if headline mentions a conflict region far from the article's stored location
      event_loc = detect_event_location(a.title)
      # Also check: article geocoded to a media capital but headline mentions a conflict zone
      event_loc ||= reaction_city_rebucket(a)
      if event_loc
        event_cell = cell_key(event_loc[0], event_loc[1])
        stored_cell = cell_key(a.latitude, a.longitude)
        if event_cell != stored_cell
          # Article is about a conflict elsewhere — count it toward the event location
          cells[event_cell] << a
          next
        end
      end
      cells[cell_key(a.latitude, a.longitude)] << a
    end

    now = Time.current
    zones = cells.filter_map do |key, events|
      next if events.size < MIN_ARTICLES

      lat, lng = key.split(",").map(&:to_f)
      centroid_lat = lat + CELL_SIZE / 2.0
      centroid_lng = lng + CELL_SIZE / 2.0

      # Rolling windows
      articles_24h = events.select { |e| e.published_at > 24.hours.ago }
      articles_48h = events.select { |e| e.published_at > 48.hours.ago }
      count_24h = articles_24h.size
      count_7d = events.size

      next if count_24h == 0 && articles_48h.size < MIN_ARTICLES

      # Source diversity — use outlet name (not pipeline label) for true diversity
      # "rss" is one pipeline but serves 120+ outlets (Reuters, BBC, Al Jazeera etc.)
      outlet_names = articles_24h.filter_map(&:name).map { |n| n.split(" (").first.strip }.uniq
      # Fall back to pipeline source if no names
      sources_24h = outlet_names.any? ? outlet_names : articles_24h.map(&:source).compact.uniq
      next if sources_24h.size < MIN_SOURCES

      # Weighted article count (tier 1 = 3x, tier 2 = 2x, etc.)
      weighted_24h = articles_24h.sum { |a| article_weight(a) }
      weighted_7d = events.sum { |a| article_weight(a) }

      # Frequency spike (using weighted counts)
      baseline_rate = weighted_7d / 7.0
      spike_ratio = weighted_24h / [baseline_rate, 1.0].max

      # Tone (weighted by credibility — tier 1 tone matters more)
      weighted_tones = articles_24h.filter_map { |a| a.tone ? [a.tone * article_weight(a), article_weight(a)] : nil }
      if weighted_tones.any?
        total_weight = weighted_tones.sum(&:last)
        avg_tone = weighted_tones.sum(&:first) / total_weight
      else
        avg_tone = 0.0
      end

      tones_prev = events.select { |e| e.published_at&.between?(48.hours.ago, 24.hours.ago) }.filter_map(&:tone)
      prev_tone = tones_prev.any? ? tones_prev.sum / tones_prev.size.to_f : 0.0

      # Distinct stories
      story_clusters = articles_24h.filter_map(&:story_cluster_id).uniq
      story_count = [story_clusters.size, articles_24h.map(&:title).uniq.size].max

      # Categories breakdown
      categories = articles_24h.group_by(&:category).transform_values(&:size)

      # Cross-layer signals
      signals = cross_layer_signals(centroid_lat, centroid_lng)

      # Tier breakdown for transparency
      tier_counts = articles_24h.each_with_object(Hash.new(0)) { |a, h| h[extract_tier(a)] += 1 }

      # Pulse score (0-100) — weighted
      freq_score = [weighted_24h / 6.0 * 25, 25].min        # 6 weighted = max (e.g., 2 tier-1 articles)
      spike_score = [spike_ratio / 4.0 * 25, 25].min
      tone_score = [avg_tone.abs / 7.0 * 15, 15].min
      diversity_score = [sources_24h.size / 5.0 * 10, 10].min
      cluster_score = [story_count / 4.0 * 10, 10].min
      cross_score = [signals.size * 5, 15].min

      # Sustained intensity bonus: high-volume zones are critical even without a spike
      # 20+ weighted articles/24h = ongoing major event (war, large-scale conflict)
      intensity_bonus = if weighted_24h >= 50 then 20
                        elsif weighted_24h >= 20 then 12
                        elsif weighted_24h >= 10 then 5
                        else 0
                        end

      pulse_score = [(freq_score + spike_score + tone_score + diversity_score + cluster_score + cross_score + intensity_bonus).round(0), 100].min

      next if pulse_score < MIN_PULSE_SCORE

      # Escalation trend
      tone_worsening = avg_tone < prev_tone - 0.5
      escalation_trend = if spike_ratio > 4.0 && tone_worsening
        "surging"
      elsif spike_ratio > 2.0 || tone_worsening
        "escalating"
      elsif weighted_24h >= 20 || pulse_score >= 70
        "active"
      elsif pulse_score >= 20
        "elevated"
      else
        "baseline"
      end

      # Top articles — prefer high-tier sources, include URL for clickthrough
      top_articles = articles_24h
        .sort_by { |a| [-extract_tier_num(a), -a.published_at.to_i] }
        .uniq(&:title).first(5)
      top_headlines = top_articles.map(&:title)

      {
        cell_key: key,
        lat: centroid_lat.round(2),
        lng: centroid_lng.round(2),
        pulse_score: pulse_score,
        escalation_trend: escalation_trend,
        count_24h: count_24h,
        weighted_24h: weighted_24h.round(1),
        count_7d: count_7d,
        spike_ratio: spike_ratio.round(1),
        avg_tone: avg_tone.round(1),
        source_count: sources_24h.size,
        story_count: story_count,
        tier_breakdown: tier_counts,
        top_headlines: top_headlines,
        top_articles: top_articles.map { |a| { title: a.title, url: a.url, source: a.source, tone: a.tone&.round(1), published_at: a.published_at&.iso8601 } },
        categories: categories,
        cross_layer_signals: signals,
        signal_context: signal_descriptions(signals),
        detected_at: now.iso8601,
      }
    end

    zones.sort_by { |z| -z[:pulse_score] }.first(MAX_RESULTS)
  end

  private

  # Conflict-specific location keywords with coordinates.
  # These are active conflict zones — when a headline mentions them,
  # the article is ABOUT this place regardless of where the reporter is.
  EVENT_LOCATIONS = {
    # Preposition patterns: "war in Iran", "strikes on Gaza", "attack in Baghdad"
    "iran" => [35.7, 51.4], "tehran" => [35.7, 51.4], "teheran" => [35.7, 51.4],
    "israel" => [31.8, 35.2], "israil" => [31.8, 35.2], "israël" => [31.8, 35.2],
    "tel aviv" => [32.1, 34.8],
    "gaza" => [31.5, 34.5], "west bank" => [31.9, 35.3],
    "ukraine" => [50.4, 30.5], "kyiv" => [50.4, 30.5], "kiev" => [50.4, 30.5],
    "oykrania" => [50.4, 30.5], "ucrania" => [50.4, 30.5], "oukrania" => [50.4, 30.5],
    "kharkiv" => [50.0, 36.2], "donbas" => [48.0, 37.8],
    "russia" => [55.8, 37.6], "moscow" => [55.8, 37.6],
    "iraq" => [33.3, 44.4], "baghdad" => [33.3, 44.4],
    "syria" => [33.5, 36.3], "damascus" => [33.5, 36.3],
    "lebanon" => [33.9, 35.5], "beirut" => [33.9, 35.5],
    "yemen" => [15.4, 44.2], "sanaa" => [15.4, 44.2],
    "sudan" => [15.6, 32.5], "khartoum" => [15.6, 32.5],
    "myanmar" => [19.8, 96.1],
    "afghanistan" => [34.5, 69.2], "kabul" => [34.5, 69.2],
    "pakistan" => [33.7, 73.0],
    "somalia" => [2.0, 45.3], "mogadishu" => [2.0, 45.3],
    "libya" => [32.9, 13.2],
    "hormuz" => [26.6, 56.3], "strait of hormuz" => [26.6, 56.3],
    "red sea" => [20.0, 38.0],
    "taiwan" => [25.0, 121.5],
    "north korea" => [39.0, 125.8],
    "kuwait" => [29.4, 48.0],
    "cuba" => [23.1, -82.4],
  }.freeze

  # Prepositions that signal the event happened AT the following location
  EVENT_PREPOSITIONS = /\b(?:in|on|at|near|over|across|from|against|hits?|strikes?|attacks?|bombs?|invades?)\s+/i

  def detect_event_location(title)
    return nil if title.blank?
    lower = title.downcase

    # First try preposition + location ("war in Iran", "strikes on Gaza")
    EVENT_LOCATIONS.each do |keyword, coords|
      if lower.match?(/#{EVENT_PREPOSITIONS}#{Regexp.escape(keyword)}\b/i)
        return coords
      end
    end

    # Fallback: any mention of an active conflict zone gets credit
    # but only for very specific conflict location names (not country names that could be the source)
    specific_locations = %w[gaza hormuz donbas kharkiv kyiv baghdad beirut sanaa mogadishu kabul damascus]
    specific_locations.each do |loc|
      return EVENT_LOCATIONS[loc] if lower.include?(loc)
    end

    nil
  end

  # If an article is geocoded far from any known conflict zone but its headline
  # mentions one, re-bucket it to that zone. This catches "EU discusses Iran war"
  # in Brussels, "Berlin debates Hormuz" etc. without hardcoding media capitals.
  def reaction_city_rebucket(article)
    return nil if article.title.blank?

    # Is the article already near a conflict zone? If so, no re-bucketing needed.
    EVENT_LOCATIONS.each_value do |coords|
      return nil if (article.latitude - coords[0]).abs < 5 && (article.longitude - coords[1]).abs < 5
    end

    # Article is far from all conflict zones — check if headline mentions one
    lower = article.title.downcase
    EVENT_LOCATIONS.each do |keyword, coords|
      return coords if lower.include?(keyword)
    end
    nil
  end

  def cell_key(lat, lng)
    "#{(lat / CELL_SIZE).floor * CELL_SIZE},#{(lng / CELL_SIZE).floor * CELL_SIZE}"
  end

  def article_weight(article)
    tier = extract_tier_num(article)
    weight = TIER_WEIGHTS[tier] || DEFAULT_WEIGHT

    # Discount high-propaganda sources (RT, TASS, Xinhua, etc.)
    cred = article.credibility.to_s
    weight *= HIGH_RISK_DISCOUNT if cred.include?("high")

    weight
  end

  def extract_tier(article)
    "tier#{extract_tier_num(article)}"
  end

  def extract_tier_num(article)
    cred = article.credibility.to_s
    match = cred.match(/tier(\d)/)
    match ? match[1].to_i : 4 # unknown = tier 4
  end

  def bbox(lat, lng, radius_km)
    dlat = radius_km / 111.0
    dlng = radius_km / (111.0 * Math.cos(lat * Math::PI / 180)).abs
    { lamin: lat - dlat, lamax: lat + dlat, lomin: lng - dlng, lomax: lng + dlng }
  end

  SIGNAL_DESCRIPTIONS = {
    military_flights: "Military aircraft on patrol or reconnaissance near active hostilities",
    gps_jamming: "Electronic warfare degrading civilian aviation navigation in the region",
    internet_outage: "Major internet disruption — possible infrastructure damage or state censorship",
    fire_hotspots: "Satellite-detected fires consistent with airstrikes or burning infrastructure",
    known_conflict_zone: "Historical conflict events from UCDP database — baseline for current escalation",
  }.freeze

  def signal_descriptions(signals)
    signals.each_with_object({}) do |(key, _val), ctx|
      ctx[key] = SIGNAL_DESCRIPTIONS[key] if SIGNAL_DESCRIPTIONS[key]
    end
  end

  def cross_layer_signals(lat, lng)
    bounds = bbox(lat, lng, 250)
    signals = {}

    mil = Flight.within_bounds(bounds).where(military: true).where("updated_at > ?", 6.hours.ago).count
    signals[:military_flights] = mil if mil > 0

    jam = GpsJammingSnapshot.where("recorded_at > ? AND percentage > 10", 6.hours.ago)
      .where(cell_lat: bounds[:lamin]..bounds[:lamax], cell_lng: bounds[:lomin]..bounds[:lomax])
    signals[:gps_jamming] = jam.maximum(:percentage)&.round(0) if jam.any?

    CrossLayerAnalyzer::COUNTRY_CENTROIDS.each do |code, (clat, clng)|
      next unless clat.between?(bounds[:lamin], bounds[:lamax]) && clng.between?(bounds[:lomin], bounds[:lomax])
      outage = InternetOutage.where(entity_code: code).where("started_at > ? AND level IN (?)", 24.hours.ago, %w[critical major])
      if outage.any?
        signals[:internet_outage] = outage.first.entity_name
        break
      end
    end

    fires = FireHotspot.where("acq_datetime > ?", 24.hours.ago)
      .where(latitude: bounds[:lamin]..bounds[:lamax], longitude: bounds[:lomin]..bounds[:lomax]).count
    signals[:fire_hotspots] = fires if fires > 5

    historical = ConflictEvent.within_bounds(bounds).count
    signals[:known_conflict_zone] = historical if historical > 10

    signals
  rescue => e
    Rails.logger.warn("ConflictPulseService cross-layer error: #{e.message}")
    {}
  end

  # Build hex cells for theater visualization using a global flat-top hex grid.
  # Vertex positions use cos(vertex_lat) so shared vertices between adjacent
  # cells produce EXACT same coordinates — guaranteeing flush tiling.
  HEX_RADIUS = 1.5                        # center-to-vertex in degrees latitude
  HEX_ROW_H  = HEX_RADIUS * Math.sqrt(3) # row spacing in degrees latitude
  # Reference cos for grid snapping (column spacing) — use median conflict latitude
  COS_REF    = Math.cos(35.0 * Math::PI / 180)
  HEX_COL_W  = HEX_RADIUS * 1.5 / COS_REF

  def build_hex_cells
    articles = NewsEvent.where("published_at > ?", 7.days.ago)
      .where.not(latitude: nil, longitude: nil)
      .where(category: CONFLICT_CATEGORIES)
      .select(:id, :latitude, :longitude, :published_at, :tone)

    cells = {}
    articles.find_each do |a|
      next if a.tone && a.tone.abs < MIN_TONE

      # Snap to global hex grid
      col = (a.longitude / HEX_COL_W).round
      vert_offset = col.odd? ? HEX_ROW_H / 2.0 : 0.0
      row = ((a.latitude - vert_offset) / HEX_ROW_H).round

      center_lat = row * HEX_ROW_H + vert_offset
      center_lng = col * HEX_COL_W

      key = "#{row},#{col}"
      cells[key] ||= { lat: center_lat, lng: center_lng, count: 0 }
      cells[key][:count] += 1
    end

    return [] if cells.empty?
    max_log = Math.log(cells.values.map { |c| c[:count] }.max + 1)

    cells.filter_map do |_key, cell|
      next if cell[:count] < 2
      {
        lat: cell[:lat],
        lng: cell[:lng],
        count: cell[:count],
        intensity: (Math.log(cell[:count] + 1) / max_log).round(2),
        vertices: hex_vertices(cell[:lat], cell[:lng]),
      }
    end
  end

  # Compute 6 vertices of a flat-top hex. Each vertex uses cos(vertex_lat)
  # for its longitude offset — so two adjacent cells sharing a vertex
  # compute the EXACT same position (because the shared vertex has the
  # same latitude from either cell). This guarantees flush tiling.
  def hex_vertices(center_lat, center_lng)
    6.times.map do |i|
      angle = (Math::PI / 3) * i
      vlat = center_lat + HEX_RADIUS * Math.sin(angle)
      cos_vlat = Math.cos(vlat * Math::PI / 180).abs
      cos_vlat = [cos_vlat, 0.05].max
      vlng = center_lng + HEX_RADIUS * Math.cos(angle) / cos_vlat
      [vlat.round(4), vlng.round(4)]
    end
  end

  # Snap arc endpoints to nearest zone centroid so arcs connect the situation bubbles.
  # If no zone is within 15° (~1600km), keep the original ACTORS coordinate but
  # drop the arc entirely if neither endpoint has a nearby zone.
  def snap_arcs_to_zones(arcs, zones)
    return arcs if zones.empty?

    max_dist = 15.0 # degrees — generous match radius

    find_nearest = ->(lat, lng) {
      best = nil
      best_d = max_dist
      zones.each do |z|
        d = Math.sqrt((z[:lat] - lat)**2 + (z[:lng] - lng)**2)
        if d < best_d
          best_d = d
          best = z
        end
      end
      best
    }

    arcs.filter_map do |arc|
      from_zone = find_nearest.call(arc[:from_lat], arc[:from_lng])
      to_zone = find_nearest.call(arc[:to_lat], arc[:to_lng])

      # Drop arcs where neither endpoint is near a zone
      next if from_zone.nil? && to_zone.nil?
      # Drop arcs that would collapse to same zone
      next if from_zone && to_zone && from_zone[:cell_key] == to_zone[:cell_key]

      arc.merge(
        from_lat: from_zone ? from_zone[:lat] : arc[:from_lat],
        from_lng: from_zone ? from_zone[:lng] : arc[:from_lng],
        from_zone_key: from_zone&.dig(:cell_key),
        to_lat: to_zone ? to_zone[:lat] : arc[:to_lat],
        to_lng: to_zone ? to_zone[:lng] : arc[:to_lng],
        to_zone_key: to_zone&.dig(:cell_key),
      )
    end
  end

  # Tag each hex cell with its nearest zone's cell_key and situation_name
  def link_hexes_to_zones(hex_cells, zones)
    return if zones.empty?
    hex_cells.each do |cell|
      best = nil
      best_d = Float::INFINITY
      zones.each do |z|
        d = (z[:lat] - cell[:lat])**2 + (z[:lng] - cell[:lng])**2
        if d < best_d
          best_d = d
          best = z
        end
      end
      if best && best_d < 400 # within ~20° — generous to catch theater hexes
        cell[:zone_key] = best[:cell_key]
        cell[:situation] = best[:situation_name]
        cell[:theater] = best[:theater]
      end
    end
  end

  def resolve_situation_name(zone)
    lat = zone[:lat]
    lng = zone[:lng]

    # 1. Check specific situation names first
    SITUATION_NAMES.each do |name, bounds|
      return name if bounds[:lat].cover?(lat) && bounds[:lng].cover?(lng)
    end

    # 2. Fallback: extract most-mentioned location from top headlines
    headlines = (zone[:top_headlines] || []).join(" ").downcase
    best_match = nil
    best_count = 0
    StrikeArcExtractor::ACTORS.each do |keyword, info|
      count = headlines.scan(keyword).size
      if count > best_count
        best_count = count
        best_match = info[:name]
      end
    end
    return "#{best_match} Region" if best_match

    # 3. Country-bounds lookup
    COUNTRY_BOUNDS.each do |name, bounds|
      return name if bounds[:lat].cover?(lat) && bounds[:lng].cover?(lng)
    end

    # 4. Last resort — latitude-based region label
    if lat > 60 then "Arctic Region"
    elsif lat > 30 then "Northern #{lng > 0 ? 'Eastern' : 'Western'} Region"
    elsif lat > -30 then "Tropical #{lng > 0 ? 'Eastern' : 'Western'} Region"
    else "Southern #{lng > 0 ? 'Eastern' : 'Western'} Region"
    end
  end
end
