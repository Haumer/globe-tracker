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

  # Situation names — map cell regions to human-readable labels
  SITUATION_NAMES = {
    "Israel-Palestine" => { lat: 30..33, lng: 34..36 },
    "Iran Theater" => { lat: 34..37, lng: 50..54 },
    "Lebanon-Israel Border" => { lat: 33..35, lng: 35..36 },
    "Eastern Ukraine Front" => { lat: 48..52, lng: 34..40 },
    "Kyiv Region" => { lat: 50..52, lng: 29..32 },
    "Moscow / Western Russia" => { lat: 54..57, lng: 36..40 },
    "Iraq Theater" => { lat: 32..35, lng: 43..46 },
    "Gaza Strip" => { lat: 30..32, lng: 34..35 },
    "Strait of Hormuz" => { lat: 25..28, lng: 55..58 },
    "Red Sea / Bab el-Mandeb" => { lat: 12..16, lng: 42..46 },
    "Gulf States" => { lat: 23..26, lng: 46..56 },
    "Sudan / Khartoum" => { lat: 14..17, lng: 31..34 },
    "Pakistan-Afghanistan" => { lat: 32..36, lng: 68..74 },
    "Myanmar" => { lat: 18..22, lng: 94..98 },
    "Cuba" => { lat: 22..24, lng: -84..-82 },
    "Washington DC" => { lat: 38..40, lng: -78..-76 },
    "Taiwan Strait" => { lat: 23..26, lng: 118..122 },
    "Korean Peninsula" => { lat: 37..40, lng: 125..128 },
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

    # Assign situation names to zones
    zones.each { |z| z[:situation_name] = resolve_situation_name(z) }

    # Extract strike arcs from all conflict headlines (last 7 days)
    all_headlines = NewsEvent.where("published_at > ?", 7.days.ago)
      .where(category: CONFLICT_CATEGORIES)
      .where.not(title: [nil, ""])
      .pluck(:title)
    strike_arcs = StrikeArcExtractor.extract(all_headlines)

    # Build hex cells for theater visualization (lower threshold than zones)
    hex_cells = build_hex_cells

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
    "iran" => [35.7, 51.4], "tehran" => [35.7, 51.4],
    "israel" => [31.8, 35.2], "tel aviv" => [32.1, 34.8],
    "gaza" => [31.5, 34.5], "west bank" => [31.9, 35.3],
    "ukraine" => [50.4, 30.5], "kyiv" => [50.4, 30.5], "kiev" => [50.4, 30.5],
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

  # Build hex cells for theater visualization — lower threshold than zones
  def build_hex_cells
    articles = NewsEvent.where("published_at > ?", 7.days.ago)
      .where.not(latitude: nil, longitude: nil)
      .where(category: CONFLICT_CATEGORIES)
      .select(:id, :latitude, :longitude, :published_at, :tone)

    cells = Hash.new(0)
    articles.find_each do |a|
      next if a.tone && a.tone.abs < MIN_TONE
      key = cell_key(a.latitude, a.longitude)
      cells[key] += 1
    end

    return [] if cells.empty?
    max_count = cells.values.max.to_f

    cells.filter_map do |key, count|
      next if count < 2
      lat, lng = key.split(",").map(&:to_f)
      {
        lat: lat + CELL_SIZE / 2.0,
        lng: lng + CELL_SIZE / 2.0,
        count: count,
        intensity: (count / max_count).round(2),
      }
    end
  end

  def resolve_situation_name(zone)
    lat = zone[:lat]
    lng = zone[:lng]

    # Check static situation names
    SITUATION_NAMES.each do |name, bounds|
      return name if bounds[:lat].cover?(lat) && bounds[:lng].cover?(lng)
    end

    # Fallback: extract most-mentioned location from top headlines
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

    best_match ? "#{best_match} Region" : nil
  end
end
