require "net/http"
require "json"
require "set"

class MultiNewsService
  include TimelineRecorder
  include NewsDedupable
  include NewsGeocodable

  REFRESH_INTERVAL = 30.minutes

  # ── Source Configurations ──────────────────────────────────────
  # Each source defines:
  #   env_key:       ENV variable name for the API key (nil = no key needed)
  #   base_url:      API endpoint
  #   params:        lambda(key) -> hash of query params
  #   articles_path: lambda(data) -> array of raw articles from the response
  #   mapping:       lambda(article) -> hash with :url, :title, :country, :name, :tone, :published_at, :themes
  API_SOURCES = [
    {
      name: "worldnews",
      env_key: "WORLDNEWS_API_KEY",
      base_url: "https://api.worldnewsapi.com/search-news",
      params: ->(key) {
        {
          "api-key" => key,
          "language" => "en",
          "sort" => "publish-time",
          "sort-direction" => "DESC",
          "number" => 100,
          "earliest-publish-date" => 24.hours.ago.strftime("%Y-%m-%d %H:%M:%S"),
        }
      },
      articles_path: ->(data) { data["news"] },
      mapping: ->(a) {
        {
          url: a["url"],
          title: a["title"],
          country: a["source_country"],
          name: a["source_country"] || a["author"],
          tone: MultiNewsService.sentiment_to_tone(a["sentiment"]),
          published_at: a["publish_date"],
          themes: ThreatClassifier.classify("#{a['title']} #{a['text']&.to_s&.first(500)}")[:keywords].first(5),
        }
      },
    },
    {
      name: "worldnews-au,nz",
      env_key: "WORLDNEWS_API_KEY",
      base_url: "https://api.worldnewsapi.com/search-news",
      params: ->(key) {
        {
          "api-key" => key,
          "language" => "en",
          "source-countries" => "au,nz",
          "sort" => "publish-time",
          "sort-direction" => "DESC",
          "number" => 50,
          "earliest-publish-date" => 24.hours.ago.strftime("%Y-%m-%d %H:%M:%S"),
        }
      },
      articles_path: ->(data) { data["news"] },
      mapping: ->(a) {
        {
          url: a["url"],
          title: a["title"],
          country: a["source_country"],
          name: a["source_country"] || a["author"],
          tone: MultiNewsService.sentiment_to_tone(a["sentiment"]),
          published_at: a["publish_date"],
          themes: ThreatClassifier.classify("#{a['title']} #{a['text']&.to_s&.first(500)}")[:keywords].first(5),
        }
      },
    },
    {
      name: "currents",
      env_key: "CURRENTS_API_KEY",
      base_url: "https://api.currentsapi.services/v1/latest-news",
      params: ->(key) {
        { apiKey: key, language: "en", page_size: 100 }
      },
      articles_path: ->(data) { data["news"] },
      mapping: ->(a) {
        countries = a["country"]
        country_name = countries.is_a?(Array) ? countries.first : countries
        {
          url: a["url"],
          title: a["title"],
          country: country_name,
          name: country_name || a["author"],
          tone: 0.0,
          published_at: a["published"],
          themes: (a["category"] || []).first(5),
        }
      },
    },
    {
      name: "thenewsapi",
      env_key: "THENEWSAPI_API_KEY",
      base_url: "https://api.thenewsapi.com/v1/news/all",
      params: ->(key) {
        { api_token: key, language: "en", limit: 50, sort: "published_at" }
      },
      articles_path: ->(data) { data["data"] },
      mapping: ->(a) {
        {
          url: a["url"],
          title: a["title"],
          country: a["locale"],
          name: a["source"],
          tone: 0.0,
          published_at: a["published_at"],
          themes: (a["categories"] || []).first(5),
        }
      },
    },
    {
      name: "gnews",
      env_key: "GNEWS_API_KEY",
      base_url: "https://gnews.io/api/v4/top-headlines",
      params: ->(key) {
        { apikey: key, lang: "en", max: 10, sortby: "publishedAt" }
      },
      articles_path: ->(data) { data["articles"] },
      mapping: ->(a) {
        {
          url: a["url"],
          title: a["title"],
          country: nil,
          name: a.dig("source", "name"),
          tone: 0.0,
          published_at: a["publishedAt"],
          themes: [],
        }
      },
    },
    {
      name: "mediastack",
      env_key: "MEDIASTACK_API_KEY",
      base_url: "http://api.mediastack.com/v1/news",
      params: ->(key) {
        { access_key: key, languages: "en", limit: 50, sort: "published_desc" }
      },
      articles_path: ->(data) { data["data"] },
      mapping: ->(a) {
        {
          url: a["url"],
          title: a["title"],
          country: a["country"],
          name: a["source"],
          tone: 0.0,
          published_at: a["published_at"],
          themes: (a["category"]&.split(",") || []).first(5),
        }
      },
    },
    {
      name: "hackernews",
      env_key: nil,
      base_url: "https://hn.algolia.com/api/v1/search",
      params: ->(_key) {
        { tags: "story", hitsPerPage: 50, numericFilters: "points>20" }
      },
      articles_path: ->(data) { data["hits"] },
      mapping: ->(a) {
        {
          url: a["url"],
          title: a["title"],
          country: nil,
          name: "Hacker News (#{a['points']} pts)",
          tone: 0.0,
          published_at: a["created_at"],
          themes: a["_tags"]&.select { |t| t.start_with?("story") } || [],
        }
      },
    },
  ].freeze

  class << self
    def refresh_if_stale(force: false)
      return 0 if !force && !stale?
      new.refresh_all
    end

    def stale?
      last = Rails.cache.read("multi_news_last_fetch")
      last.nil? || last < REFRESH_INTERVAL.ago
    end

    # Used by source mapping lambdas
    def sentiment_to_tone(sentiment)
      return 0.0 if sentiment.nil?
      (sentiment.to_f * 10).round(1)
    end
  end

  def refresh_all
    all_records = []

    API_SOURCES.each do |source_config|
      all_records.concat(fetch_source(source_config))
    end

    return 0 if all_records.empty?

    # Dedup against existing DB records by URL
    existing_urls = NewsEvent.where(url: all_records.map { |r| r[:url] }).pluck(:url).to_set
    new_records = all_records.reject { |r| existing_urls.include?(r[:url]) }

    # Cross-source dedup by normalized title similarity (including DB titles from GDELT etc.)
    existing_titles = NewsEvent.where("published_at > ?", 48.hours.ago)
      .pluck(:title).compact
      .map { |t| normalize_title(t) }
    new_records = dedup_by_title(new_records, existing_titles: existing_titles)

    # Apply threat classification and credibility
    new_records.each do |record|
      threat = ThreatClassifier.classify(record[:title].to_s)
      record[:threat_level] ||= threat[:threat]
      record[:credibility] ||= "tier2/low" # API sources are generally tier 2
    end

    assign_clusters(new_records)

    if new_records.any?
      NewsEvent.upsert_all(new_records, unique_by: :url)
      record_timeline_events(
        event_type: "news",
        model_class: NewsEvent,
        unique_key: :url,
        unique_values: new_records.map { |r| r[:url] },
        time_column: :published_at
      )

      TrendingKeywordTracker.ingest(new_records) if defined?(TrendingKeywordTracker)
    end

    Rails.cache.write("multi_news_last_fetch", Time.current)
    new_records.size
  rescue => e
    Rails.logger.error("MultiNewsService: #{e.message}")
    0
  end

  private

  # ── Generic source fetcher ────────────────────────────────────
  def fetch_source(config)
    source_name = config[:name]

    # Check API key requirement
    if config[:env_key]
      key = ENV[config[:env_key]]
      return [] if key.blank?
    end

    uri = URI(config[:base_url])
    uri.query = URI.encode_www_form(config[:params].call(key))

    data = fetch_json(uri)
    articles = config[:articles_path].call(data) if data
    return [] unless articles

    source_label = source_name.split("-").first # "worldnews-au,nz" -> "worldnews"

    articles.filter_map do |article|
      mapped = config[:mapping].call(article)
      next if mapped[:url].blank?

      lat, lng = resolve_location(mapped[:country], mapped[:title], mapped[:url])
      next unless lat && lng

      build_record(
        url: mapped[:url],
        title: mapped[:title],
        name: mapped[:name],
        lat: lat, lng: lng,
        tone: mapped[:tone],
        published_at: parse_time(mapped[:published_at]),
        themes: mapped[:themes],
        source: source_label,
      )
    end
  rescue => e
    Rails.logger.error("MultiNewsService[#{config[:name]}]: #{e.message}")
    []
  end

  # ── Helpers ───────────────────────────────────────────────────

  def fetch_json(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.open_timeout = 10
    http.read_timeout = 15
    req = Net::HTTP::Get.new(uri)
    res = http.request(req)
    return nil unless res.is_a?(Net::HTTPSuccess)
    JSON.parse(res.body.force_encoding("UTF-8"))
  rescue => e
    Rails.logger.error("MultiNewsService fetch error (#{uri.host}): #{e.message}")
    nil
  end

  def build_record(url:, title:, name:, lat:, lng:, tone:, published_at:, themes:, source:)
    now = Time.current
    tone_val = tone.to_f
    {
      url: url,
      title: title&.truncate(500),
      name: name&.truncate(200),
      latitude: lat,
      longitude: lng,
      tone: tone_val.round(1),
      level: ThreatClassifier.tone_level(tone_val),
      category: ThreatClassifier.classify(title)[:category],
      themes: themes.is_a?(Array) ? themes : [],
      published_at: published_at || now,
      fetched_at: now,
      source: source,
      created_at: now,
      updated_at: now,
    }
  end

  def parse_time(str)
    return nil if str.blank?
    Time.parse(str.to_s)
  rescue ArgumentError
    nil
  end

end
