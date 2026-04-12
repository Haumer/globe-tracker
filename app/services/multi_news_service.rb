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
          summary: a["text"] || a["summary"] || a["description"],
          country: a["source_country"],
          name: a["source_country"] || a["author"],
          tone: MultiNewsService.sentiment_to_tone(a["sentiment"]),
          published_at: a["publish_date"],
          category: "world",
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
          summary: a["text"] || a["summary"] || a["description"],
          country: a["source_country"],
          name: a["source_country"] || a["author"],
          tone: MultiNewsService.sentiment_to_tone(a["sentiment"]),
          published_at: a["publish_date"],
          category: "world",
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
          summary: a["description"],
          country: country_name,
          name: country_name || a["author"],
          tone: 0.0,
          published_at: a["published"],
          category: (a["category"] || []).first,
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
          summary: a["description"] || a["snippet"],
          country: a["locale"],
          name: a["source"],
          tone: 0.0,
          published_at: a["published_at"],
          category: (a["categories"] || []).first,
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
          summary: a["description"] || a["content"],
          country: nil,
          name: a.dig("source", "name"),
          tone: 0.0,
          published_at: a["publishedAt"],
          category: "top_headlines",
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
          summary: a["description"],
          country: a["country"],
          name: a["source"],
          tone: 0.0,
          published_at: a["published_at"],
          category: a["category"],
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
          summary: nil,
          country: nil,
          name: "Hacker News (#{a['points']} pts)",
          tone: 0.0,
          published_at: a["created_at"],
          category: "technology",
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
    ingest_items = []

    API_SOURCES.each do |source_config|
      result = fetch_source(source_config)
      all_records.concat(result[:records])
      ingest_items.concat(result[:ingest_items])
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

    ingest_ids = NewsIngestRecorder.record_all(ingest_items)
    new_records.each { |record| record[:news_ingest_id] = ingest_ids[record[:url]] }
    normalized_ids = NewsNormalizationRecorder.record_all(new_records)
    new_records.each do |record|
      ids = normalized_ids[record[:url]]
      next unless ids

      record[:news_source_id] = ids[:news_source_id]
      record[:news_article_id] = ids[:news_article_id]
      record[:content_scope] = ids[:content_scope]
    end
    NewsClaimRecorder.record_all(new_records)

    assign_clusters(new_records)
    NewsOntologySyncService.enqueue_for_records(new_records)

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
    now = Time.current

    # Check API key requirement
    if config[:env_key]
      key = ENV[config[:env_key]]
      if key.blank?
        SourceFeedStatusRecorder.record(
          provider: "multi-news",
          display_name: source_name,
          feed_kind: "api",
          endpoint_url: config[:base_url],
          status: "disabled",
          metadata: { env_key: config[:env_key] },
          occurred_at: now
        )
        return empty_fetch_result
      end
    end

    uri = URI(config[:base_url])
    uri.query = URI.encode_www_form(config[:params].call(key))

    response = fetch_json(uri)
    response_data = response&.dig(:data)
    articles = response_data.present? ? Array(config[:articles_path].call(response_data)) : nil
    unless articles
      SourceFeedStatusRecorder.record(
        provider: "multi-news",
        display_name: source_name,
        feed_kind: "api",
        endpoint_url: config[:base_url],
        status: "error",
        http_status: response&.dig(:http_status),
        error_message: response&.dig(:error_message) || "No article payload returned",
        metadata: { source_adapter: source_name },
        occurred_at: now
      )
      return empty_fetch_result
    end

    source_label = source_name.split("-").first # "worldnews-au,nz" -> "worldnews"
    records = []
    ingest_items = []

    articles.each_with_index do |article, idx|
      next unless article.is_a?(Hash)

      raw_mapped = config[:mapping].call(article)
      next unless raw_mapped.is_a?(Hash)

      raw_url = article["url"] || raw_mapped[:url]
      raw_title = article["title"] || raw_mapped[:title]
      next if raw_url.blank? || raw_title.blank?

      mapped = NewsSourceAdapter.normalize!(
        source_adapter: source_name,
        attrs: raw_mapped.merge(
          summary: article["description"] || article["text"] || article["summary"] || article["content"] || raw_mapped[:summary],
          source: source_label
        )
      )
      ingest_items << {
        item_key: mapped[:url].presence || raw_url.presence || "#{source_name}-#{idx}",
        source_feed: source_name,
        source_endpoint_url: uri.to_s,
        external_id: article["id"] || article["uuid"],
        raw_url: raw_url,
        raw_title: raw_title,
        raw_summary: mapped[:summary],
        raw_published_at: mapped[:published_at] || article["publish_date"] || article["published"] || article["publishedAt"] || article["published_at"] || article["created_at"],
        fetched_at: now,
        payload_format: "json",
        raw_payload: article,
        http_status: response[:http_status],
      }
      next if mapped[:url].blank?

      location = LocationResolver.resolve_event(
        title: mapped[:title],
        summary: mapped[:summary],
        country_hint: mapped[:country],
        url: mapped[:url]
      )
      next unless location&.coordinates

      records << build_record(
        url: mapped[:url],
        title: mapped[:title],
        summary: mapped[:summary],
        name: mapped[:name],
        location: location,
        tone: mapped[:tone],
        published_at: parse_time(mapped[:published_at]),
        category: mapped[:category],
        themes: mapped[:themes],
        source: source_label,
      )
    end

    SourceFeedStatusRecorder.record(
      provider: "multi-news",
      display_name: source_name,
      feed_kind: "api",
      endpoint_url: config[:base_url],
      status: "success",
      records_fetched: articles.size,
      records_stored: records.size,
      http_status: response[:http_status],
      metadata: { source_adapter: source_name },
      occurred_at: now
    )

    { records: records, ingest_items: ingest_items }
  rescue => e
    Rails.logger.error("MultiNewsService[#{config[:name]}]: #{e.message}")
    SourceFeedStatusRecorder.record(
      provider: "multi-news",
      display_name: config[:name],
      feed_kind: "api",
      endpoint_url: config[:base_url],
      status: "error",
      error_message: e.message,
      metadata: { source_adapter: config[:name] },
      occurred_at: Time.current
    )
    empty_fetch_result
  end

  # ── Helpers ───────────────────────────────────────────────────

  def fetch_json(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.open_timeout = 10
    http.read_timeout = 15
    req = Net::HTTP::Get.new(uri)
    res = http.request(req)
    unless res.is_a?(Net::HTTPSuccess)
      return { data: nil, http_status: res.code.to_i, error_message: "HTTP #{res.code}" }
    end

    { data: JSON.parse(res.body.force_encoding("UTF-8")), http_status: res.code.to_i }
  rescue => e
    Rails.logger.error("MultiNewsService fetch error (#{uri.host}): #{e.message}")
    { data: nil, http_status: nil, error_message: e.message }
  end

  def empty_fetch_result
    { records: [], ingest_items: [] }
  end

  def build_record(url:, title:, summary:, name:, location:, tone:, published_at:, category:, themes:, source:)
    now = Time.current
    tone_val = tone.to_f
    classification_text = [ title, summary ].compact.join(" ")
    threat = ThreatClassifier.classify(classification_text)
    LocationResolver.news_event_attributes(location).merge(
      url: url,
      title: title&.truncate(500),
      name: name&.truncate(200),
      tone: tone_val.round(1),
      level: ThreatClassifier.tone_level(tone_val),
      category: preferred_category(category) || threat[:category],
      themes: themes.is_a?(Array) ? themes : [],
      published_at: published_at || now,
      fetched_at: now,
      source: source,
      created_at: now,
      updated_at: now,
    )
  end

  def parse_time(str)
    return nil if str.blank?
    Time.parse(str.to_s)
  rescue ArgumentError
    nil
  end

  def preferred_category(category)
    normalized = category.to_s.downcase.presence
    return nil if normalized.blank? || %w[world top_headlines technology general news latest].include?(normalized)

    normalized
  end

end
