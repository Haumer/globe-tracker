require "rss"
require "net/http"

class RssNewsService
  include TimelineRecorder

  REFRESH_INTERVAL = 20.minutes

  # ── Source Credibility System ────────────────────────────────
  # tier: 1=wire/gov, 2=major, 3=specialty, 4=aggregator
  # risk: low/medium/high (propaganda/bias risk)
  # affiliation: state affiliation if any

  SOURCES = {
    # ── Tier 1: Wire services & Government ──
    { url: "https://feeds.reuters.com/reuters/worldNews", name: "Reuters" } =>
      { tier: 1, risk: "low", region: "global", category: "wire" },
    { url: "https://feeds.reuters.com/reuters/topNews", name: "Reuters Top" } =>
      { tier: 1, risk: "low", region: "global", category: "wire" },
    { url: "https://rss.nytimes.com/services/xml/rss/nyt/World.xml", name: "NYT World" } =>
      { tier: 1, risk: "low", region: "us", category: "mainstream" },
    { url: "https://news.un.org/feed/subscribe/en/news/all/rss.xml", name: "UN News" } =>
      { tier: 1, risk: "low", region: "global", category: "gov" },

    # ── Tier 2: Major outlets ──
    { url: "https://feeds.bbci.co.uk/news/world/rss.xml", name: "BBC World" } =>
      { tier: 2, risk: "low", region: "global", category: "mainstream" },
    { url: "https://www.aljazeera.com/xml/rss/all.xml", name: "Al Jazeera" } =>
      { tier: 2, risk: "medium", affiliation: "Qatar", region: "global", category: "mainstream" },
    { url: "https://www.theguardian.com/world/rss", name: "Guardian World" } =>
      { tier: 2, risk: "low", region: "global", category: "mainstream" },
    { url: "https://rss.cnn.com/rss/edition_world.rss", name: "CNN World" } =>
      { tier: 2, risk: "low", region: "global", category: "mainstream" },
    { url: "https://feeds.washingtonpost.com/rss/world", name: "Washington Post" } =>
      { tier: 2, risk: "low", region: "us", category: "mainstream" },
    { url: "https://www.france24.com/en/rss", name: "France 24" } =>
      { tier: 2, risk: "medium", affiliation: "France", region: "europe", category: "mainstream" },
    { url: "https://feeds.npr.org/1004/rss.xml", name: "NPR World" } =>
      { tier: 2, risk: "low", region: "us", category: "mainstream" },

    # ── Tier 3: Specialty / OSINT / Defense ──
    { url: "https://www.bellingcat.com/feed/", name: "Bellingcat" } =>
      { tier: 3, risk: "low", region: "global", category: "osint" },
    { url: "https://www.defensenews.com/arc/outboundfeeds/rss/?outputType=xml", name: "Defense News" } =>
      { tier: 3, risk: "low", region: "us", category: "defense" },
    { url: "https://thewarzone.com/feed", name: "The War Zone" } =>
      { tier: 3, risk: "low", region: "global", category: "defense" },
    { url: "https://foreignpolicy.com/feed/", name: "Foreign Policy" } =>
      { tier: 3, risk: "low", region: "global", category: "thinktank" },
    { url: "https://www.armscontrol.org/rss.xml", name: "Arms Control Assoc." } =>
      { tier: 3, risk: "low", region: "global", category: "thinktank" },
  }.freeze

  # ── Google News RSS (free, no key, fallback) ─────────────────
  GOOGLE_NEWS_TOPICS = {
    "world" => "https://news.google.com/rss/topics/CAAqJggKIiBDQkFTRWdvSUwyMHZNRGx1YlY4U0FtVnVHZ0pWVXlnQVAB?hl=en-US&gl=US&ceid=US:en",
    "conflict" => "https://news.google.com/rss/search?q=military+OR+war+OR+conflict+OR+attack&hl=en-US&gl=US&ceid=US:en",
    "disaster" => "https://news.google.com/rss/search?q=earthquake+OR+tsunami+OR+hurricane+OR+wildfire+OR+flood&hl=en-US&gl=US&ceid=US:en",
  }.freeze

  class << self
    def refresh_if_stale(force: false)
      return 0 if !force && !stale?
      new.refresh_all
    end

    def stale?
      last = Rails.cache.read("rss_news_last_fetch")
      last.nil? || last < REFRESH_INTERVAL.ago
    end
  end

  def refresh_all
    all_records = []

    # Direct RSS feeds
    SOURCES.each do |feed_info, meta|
      records = fetch_feed(feed_info[:url], feed_info[:name], meta)
      all_records.concat(records)
    end

    # Google News fallback
    GOOGLE_NEWS_TOPICS.each do |topic, url|
      records = fetch_feed(url, "Google News (#{topic})", { tier: 4, risk: "low", region: "global", category: "aggregator" })
      all_records.concat(records)
    end

    return 0 if all_records.empty?

    # Dedup against DB
    existing_urls = NewsEvent.where(url: all_records.map { |r| r[:url] }).pluck(:url).to_set
    new_records = all_records.reject { |r| existing_urls.include?(r[:url]) }

    # Cross-source dedup by title similarity
    new_records = dedup_by_title(new_records)

    if new_records.any?
      NewsEvent.upsert_all(new_records, unique_by: :url)
      record_timeline_events(
        event_type: "news",
        model_class: NewsEvent,
        unique_key: :url,
        unique_values: new_records.map { |r| r[:url] },
        time_column: :published_at
      )

      # Track trending keywords
      TrendingKeywordTracker.ingest(new_records) if defined?(TrendingKeywordTracker)
    end

    Rails.cache.write("rss_news_last_fetch", Time.current)
    new_records.size
  rescue => e
    Rails.logger.error("RssNewsService: #{e.message}")
    0
  end

  private

  def fetch_feed(url, source_name, meta)
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 8
    http.read_timeout = 15

    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = "GlobeTracker/1.0 (news aggregator)"
    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.warn("RssNewsService[#{source_name}]: HTTP #{response.code}")
      return []
    end

    feed = RSS::Parser.parse(response.body, false)
    return [] unless feed

    now = Time.current
    items = (feed.items || []).first(30)

    items.filter_map do |item|
      title = item.title&.to_s&.strip
      link = item.link.is_a?(String) ? item.link : item.link&.href
      next if title.blank? || link.blank?

      # Clean Google News redirect URLs
      link = clean_google_url(link) if link.include?("news.google.com")

      lat, lng = geocode_title(title)
      next unless lat && lng

      pub_date = parse_pub_date(item)
      threat = classify_threat(title)
      credibility = credibility_label(meta[:tier], meta[:risk], meta[:affiliation])

      {
        url: link.truncate(2000),
        title: title.truncate(500),
        name: source_name.truncate(200),
        latitude: lat + rand(-0.1..0.1),
        longitude: lng + rand(-0.1..0.1),
        tone: threat[:tone],
        level: threat[:level],
        category: threat[:category],
        threat_level: threat[:threat],
        credibility: credibility,
        themes: threat[:keywords].first(5),
        published_at: pub_date || now,
        fetched_at: now,
        source: "rss",
        created_at: now,
        updated_at: now,
      }
    end
  rescue => e
    Rails.logger.warn("RssNewsService[#{source_name}]: #{e.message}")
    []
  end

  # ── Threat Classification ───────────────────────────────────

  CRITICAL_TARGETS = %w[iran russia china taiwan nato nuclear].freeze
  MILITARY_ESCALATION = %w[attack strike bomb missile launch invasion troops deployed airstrike].freeze
  CONFLICT_WORDS = %w[war battle fighting conflict killed soldiers casualties combat artillery shelling drone].freeze
  TERROR_WORDS = %w[terrorism terrorist bombing hostage hijack explosion].freeze
  PROTEST_WORDS = %w[protest rally demonstration riot uprising coup revolution rebellion].freeze
  DISASTER_WORDS = %w[earthquake tsunami hurricane tornado wildfire volcano flood cyclone landslide avalanche].freeze
  HEALTH_WORDS = %w[pandemic outbreak epidemic virus infection disease vaccine].freeze
  ECONOMY_WORDS = %w[recession inflation crash bankruptcy sanctions tariff default].freeze
  DIPLOMACY_WORDS = %w[peace ceasefire treaty summit negotiate agreement diplomatic].freeze
  CYBER_WORDS = %w[cyberattack hack breach ransomware malware ddos].freeze

  def classify_threat(title)
    lower = title.downcase
    keywords = []
    category = "other"
    threat = "info"
    tone = 0.0

    # Check categories
    if (MILITARY_ESCALATION + CONFLICT_WORDS).any? { |w| lower.include?(w) }
      category = "conflict"
      keywords = (MILITARY_ESCALATION + CONFLICT_WORDS).select { |w| lower.include?(w) }
      threat = "high"
      tone = -4.0

      # Escalate to critical if mentions critical targets + military action
      if CRITICAL_TARGETS.any? { |t| lower.include?(t) } && MILITARY_ESCALATION.any? { |w| lower.include?(w) }
        threat = "critical"
        tone = -8.0
      end
    elsif TERROR_WORDS.any? { |w| lower.include?(w) }
      category = "conflict"
      keywords = TERROR_WORDS.select { |w| lower.include?(w) }
      threat = "critical"
      tone = -7.0
    elsif DISASTER_WORDS.any? { |w| lower.include?(w) }
      category = "disaster"
      keywords = DISASTER_WORDS.select { |w| lower.include?(w) }
      threat = "high"
      tone = -3.0
    elsif PROTEST_WORDS.any? { |w| lower.include?(w) }
      category = "unrest"
      keywords = PROTEST_WORDS.select { |w| lower.include?(w) }
      threat = "medium"
      tone = -2.0
    elsif CYBER_WORDS.any? { |w| lower.include?(w) }
      category = "cyber"
      keywords = CYBER_WORDS.select { |w| lower.include?(w) }
      threat = "high"
      tone = -4.0
    elsif HEALTH_WORDS.any? { |w| lower.include?(w) }
      category = "health"
      keywords = HEALTH_WORDS.select { |w| lower.include?(w) }
      threat = "medium"
      tone = -2.0
    elsif ECONOMY_WORDS.any? { |w| lower.include?(w) }
      category = "economy"
      keywords = ECONOMY_WORDS.select { |w| lower.include?(w) }
      threat = "medium"
      tone = -2.0
    elsif DIPLOMACY_WORDS.any? { |w| lower.include?(w) }
      category = "diplomacy"
      keywords = DIPLOMACY_WORDS.select { |w| lower.include?(w) }
      threat = "low"
      tone = 1.0
    end

    { category: category, threat: threat, tone: tone.round(1), level: tone_level(tone), keywords: keywords }
  end

  # ── Source Credibility ──────────────────────────────────────

  def credibility_label(tier, risk, affiliation = nil)
    parts = ["tier#{tier}"]
    parts << risk
    parts << affiliation if affiliation.present?
    parts.join("/")
  end

  # ── Geocoding (reuse MultiNewsService patterns) ─────────────

  GEO_MAP = MultiNewsService::TITLE_GEO_MAP
  GEO_PATTERNS = GEO_MAP.keys.sort_by { |k| -k.length }.freeze
  COUNTRY_COORDS = MultiNewsService::COUNTRY_COORDS

  def geocode_title(title)
    return nil if title.blank?
    lower = title.downcase
    GEO_PATTERNS.each do |pattern|
      if lower.include?(pattern)
        code = GEO_MAP[pattern]
        return COUNTRY_COORDS[code] if code && COUNTRY_COORDS[code]
      end
    end
    nil
  end

  # ── Helpers ─────────────────────────────────────────────────

  def tone_level(tone)
    if tone <= -5 then "critical"
    elsif tone <= -2 then "negative"
    elsif tone <= 2 then "neutral"
    else "positive"
    end
  end

  def parse_pub_date(item)
    if item.respond_to?(:pubDate) && item.pubDate
      item.pubDate.is_a?(Time) ? item.pubDate : Time.parse(item.pubDate.to_s)
    elsif item.respond_to?(:updated) && item.updated
      item.updated.is_a?(Time) ? item.updated : Time.parse(item.updated.content.to_s)
    elsif item.respond_to?(:date) && item.date
      item.date
    end
  rescue
    nil
  end

  def clean_google_url(url)
    # Google News wraps real URLs — extract if possible
    if url.include?("url=")
      match = url.match(/url=([^&]+)/)
      return URI.decode_www_form_component(match[1]) if match
    end
    url
  end

  def dedup_by_title(records)
    seen = []
    records.select do |record|
      title = record[:title]
      if title.blank?
        true
      else
        words = title.downcase.gsub(/[^a-z0-9\s]/, "").split.reject { |w| w.length < 3 }.to_set
        duplicate = seen.any? { |s| jaccard(s, words) > 0.6 }
        seen << words unless duplicate
        !duplicate
      end
    end
  end

  def jaccard(set_a, set_b)
    return 0.0 if set_a.empty? || set_b.empty?
    (set_a & set_b).size.to_f / (set_a | set_b).size.to_f
  end
end
