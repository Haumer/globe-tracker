require "rss"
require "net/http"

class RssNewsService
  extend Refreshable
  include TimelineRecorder

  refreshes model: NewsEvent, interval: 20.minutes

  # ── Source Credibility System ────────────────────────────────
  SOURCES = {
    # Tier 1: Wire services & Government
    { url: "https://feeds.reuters.com/reuters/worldNews", name: "Reuters" } =>
      { tier: 1, risk: "low", region: "global" },
    { url: "https://feeds.reuters.com/reuters/topNews", name: "Reuters Top" } =>
      { tier: 1, risk: "low", region: "global" },
    { url: "https://rss.nytimes.com/services/xml/rss/nyt/World.xml", name: "NYT World" } =>
      { tier: 1, risk: "low", region: "us" },
    { url: "https://news.un.org/feed/subscribe/en/news/all/rss.xml", name: "UN News" } =>
      { tier: 1, risk: "low", region: "global" },

    # Tier 2: Major outlets
    { url: "https://feeds.bbci.co.uk/news/world/rss.xml", name: "BBC World" } =>
      { tier: 2, risk: "low", region: "global" },
    { url: "https://www.aljazeera.com/xml/rss/all.xml", name: "Al Jazeera" } =>
      { tier: 2, risk: "medium", affiliation: "Qatar", region: "global" },
    { url: "https://www.theguardian.com/world/rss", name: "Guardian World" } =>
      { tier: 2, risk: "low", region: "global" },
    { url: "https://rss.cnn.com/rss/edition_world.rss", name: "CNN World" } =>
      { tier: 2, risk: "low", region: "global" },
    { url: "https://feeds.washingtonpost.com/rss/world", name: "Washington Post" } =>
      { tier: 2, risk: "low", region: "us" },
    { url: "https://www.france24.com/en/rss", name: "France 24" } =>
      { tier: 2, risk: "medium", affiliation: "France", region: "europe" },
    { url: "https://feeds.npr.org/1004/rss.xml", name: "NPR World" } =>
      { tier: 2, risk: "low", region: "us" },

    # Tier 3: Specialty / OSINT / Defense
    { url: "https://www.bellingcat.com/feed/", name: "Bellingcat" } =>
      { tier: 3, risk: "low", region: "global" },
    { url: "https://www.defensenews.com/arc/outboundfeeds/rss/?outputType=xml", name: "Defense News" } =>
      { tier: 3, risk: "low", region: "us" },
    { url: "https://thewarzone.com/feed", name: "The War Zone" } =>
      { tier: 3, risk: "low", region: "global" },
    { url: "https://foreignpolicy.com/feed/", name: "Foreign Policy" } =>
      { tier: 3, risk: "low", region: "global" },
    { url: "https://www.armscontrol.org/rss.xml", name: "Arms Control Assoc." } =>
      { tier: 3, risk: "low", region: "global" },
  }.freeze

  GOOGLE_NEWS_TOPICS = {
    "world" => "https://news.google.com/rss/topics/CAAqJggKIiBDQkFTRWdvSUwyMHZNRGx1YlY4U0FtVnVHZ0pWVXlnQVAB?hl=en-US&gl=US&ceid=US:en",
    "conflict" => "https://news.google.com/rss/search?q=military+OR+war+OR+conflict+OR+attack&hl=en-US&gl=US&ceid=US:en",
    "disaster" => "https://news.google.com/rss/search?q=earthquake+OR+tsunami+OR+hurricane+OR+wildfire+OR+flood&hl=en-US&gl=US&ceid=US:en",
  }.freeze

  class << self
    def refresh_if_stale(force: false)
      return 0 if !force && !stale?
      new.refresh
    end

    def stale?
      last = Rails.cache.read("rss_news_last_fetch")
      last.nil? || last < 20.minutes.ago
    end
  end

  def refresh
    all_records = []

    SOURCES.each do |feed_info, meta|
      all_records.concat(fetch_feed(feed_info[:url], feed_info[:name], meta))
    end

    GOOGLE_NEWS_TOPICS.each do |topic, url|
      all_records.concat(fetch_feed(url, "Google News (#{topic})", { tier: 4, risk: "low", region: "global" }))
    end

    return 0 if all_records.empty?

    existing_urls = NewsEvent.where(url: all_records.map { |r| r[:url] }).pluck(:url).to_set
    new_records = dedup_by_title(all_records.reject { |r| existing_urls.include?(r[:url]) })

    if new_records.any?
      NewsEvent.upsert_all(new_records, unique_by: :url)
      record_timeline_events(
        event_type: "news", model_class: NewsEvent,
        unique_key: :url, unique_values: new_records.map { |r| r[:url] },
        time_column: :published_at
      )
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
    (feed.items || []).first(30).filter_map do |item|
      title = item.title&.to_s&.strip
      link = item.link.is_a?(String) ? item.link : item.link&.href
      next if title.blank? || link.blank?

      link = clean_google_url(link) if link.include?("news.google.com")

      lat, lng = geocode_title(title)
      next unless lat && lng

      threat = ThreatClassifier.classify(title)
      credibility = [("tier#{meta[:tier]}"), meta[:risk], meta[:affiliation]].compact.join("/")

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
        published_at: parse_pub_date(item) || now,
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

  # ── Geocoding (reuse MultiNewsService patterns) ─────────────

  GEO_MAP = MultiNewsService::TITLE_GEO_MAP
  GEO_PATTERNS = GEO_MAP.keys.sort_by { |k| -k.length }.freeze
  COUNTRY_COORDS = MultiNewsService::COUNTRY_COORDS

  def geocode_title(title)
    lower = title.to_s.downcase
    GEO_PATTERNS.each do |pattern|
      code = GEO_MAP[pattern]
      coords = COUNTRY_COORDS[code] if code
      return coords if coords && lower.include?(pattern)
    end
    nil
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
    match = url.match(/url=([^&]+)/) if url.include?("url=")
    match ? URI.decode_www_form_component(match[1]) : url
  end

  def dedup_by_title(records)
    seen = []
    records.select do |record|
      title = record[:title]
      next true if title.blank?
      words = title.downcase.gsub(/[^a-z0-9\s]/, "").split.reject { |w| w.length < 3 }.to_set
      duplicate = seen.any? { |s| jaccard(s, words) > 0.6 }
      seen << words unless duplicate
      !duplicate
    end
  end

  def jaccard(a, b)
    return 0.0 if a.empty? || b.empty?
    (a & b).size.to_f / (a | b).size.to_f
  end
end
