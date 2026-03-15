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

  class << self
    def analyze
      Rails.cache.fetch(CACHE_KEY, expires_in: 10.minutes) { new.compute }
    end

    def invalidate
      Rails.cache.delete(CACHE_KEY)
    end
  end

  def compute
    articles = NewsEvent.where("published_at > ?", 7.days.ago)
      .where.not(latitude: nil, longitude: nil)
      .where(category: CONFLICT_CATEGORIES)
      .select(:id, :title, :latitude, :longitude, :tone, :source, :category,
              :threat_level, :credibility, :story_cluster_id, :published_at)

    # Grid into 2° cells
    cells = Hash.new { |h, k| h[k] = [] }
    articles.find_each do |a|
      # Filter out low-intensity articles (probably miscategorized)
      next if a.tone && a.tone.abs < MIN_TONE
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

      # Source diversity (distinct sources in 24h) — require multi-source
      sources_24h = articles_24h.map(&:source).compact.uniq
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

      pulse_score = (freq_score + spike_score + tone_score + diversity_score + cluster_score + cross_score).round(0)

      next if pulse_score < MIN_PULSE_SCORE

      # Escalation trend
      tone_worsening = avg_tone < prev_tone - 0.5
      escalation_trend = if spike_ratio > 4.0 && tone_worsening
        "surging"
      elsif spike_ratio > 2.0 || tone_worsening
        "escalating"
      elsif pulse_score >= 20
        "elevated"
      else
        "baseline"
      end

      # Top headlines — prefer high-tier sources
      top_headlines = articles_24h
        .sort_by { |a| [-extract_tier_num(a), -a.published_at.to_i] }
        .map(&:title).uniq.first(5)

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
        categories: categories,
        cross_layer_signals: signals,
        detected_at: now.iso8601,
      }
    end

    zones.sort_by { |z| -z[:pulse_score] }.first(MAX_RESULTS)
  end

  private

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
end
