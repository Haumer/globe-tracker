require "net/http"
require "json"
require "set"

class MultiNewsService
  include TimelineRecorder

  # Country code → [lat, lng] for geocoding APIs that only return country
  COUNTRY_COORDS = {
    "us" => [38.9, -77.0], "gb" => [51.5, -0.1], "uk" => [51.5, -0.1],
    "fr" => [48.9, 2.3], "de" => [52.5, 13.4], "it" => [41.9, 12.5],
    "es" => [40.4, -3.7], "pt" => [38.7, -9.1], "nl" => [52.4, 4.9],
    "be" => [50.8, 4.4], "ch" => [46.9, 7.4], "at" => [48.2, 16.4],
    "se" => [59.3, 18.1], "no" => [59.9, 10.8], "dk" => [55.7, 12.6],
    "fi" => [60.2, 24.9], "pl" => [52.2, 21.0], "cz" => [50.1, 14.4],
    "hu" => [47.5, 19.0], "ro" => [44.4, 26.1], "bg" => [42.7, 23.3],
    "gr" => [37.98, 23.7], "hr" => [45.8, 16.0], "rs" => [44.8, 20.5],
    "ua" => [50.4, 30.5], "ru" => [55.8, 37.6], "tr" => [39.9, 32.9],
    "il" => [31.8, 35.2], "ae" => [25.3, 55.3], "sa" => [24.7, 46.7],
    "qa" => [25.3, 51.5], "kw" => [29.4, 47.98], "ir" => [35.7, 51.4],
    "iq" => [33.3, 44.4], "jo" => [31.95, 35.9], "lb" => [33.9, 35.5],
    "eg" => [30.0, 31.2], "za" => [-33.9, 18.4], "ng" => [9.1, 7.5],
    "ke" => [-1.3, 36.8], "et" => [9.0, 38.7], "gh" => [5.6, -0.2],
    "ma" => [34.0, -6.8], "tn" => [36.8, 10.2], "dz" => [36.8, 3.1],
    "cn" => [39.9, 116.4], "jp" => [35.7, 139.7], "kr" => [37.6, 127.0],
    "in" => [28.6, 77.2], "pk" => [33.7, 73.0], "bd" => [23.8, 90.4],
    "th" => [13.75, 100.5], "vn" => [21.0, 105.85], "ph" => [14.6, 121.0],
    "id" => [-6.2, 106.8], "my" => [3.1, 101.7], "sg" => [1.35, 103.8],
    "au" => [-33.9, 151.2], "nz" => [-41.3, 174.8],
    "ca" => [45.4, -75.7], "mx" => [19.4, -99.1], "br" => [-15.8, -47.9],
    "ar" => [-34.6, -58.4], "cl" => [-33.4, -70.6], "co" => [4.7, -74.1],
    "pe" => [-12.0, -77.0], "ve" => [10.5, -66.9],
    "ie" => [53.3, -6.3], "sk" => [48.1, 17.1], "si" => [46.05, 14.5],
    "lt" => [54.7, 25.3], "lv" => [56.95, 24.1], "ee" => [59.4, 24.7],
    "tw" => [25.0, 121.5], "hk" => [22.3, 114.2], "ly" => [32.9, 13.2],
    "sd" => [15.6, 32.5], "ug" => [0.3, 32.6], "tz" => [-6.8, 39.3],
    "mm" => [19.75, 96.1], "af" => [34.5, 69.2], "sy" => [33.5, 36.3],
    "ye" => [15.4, 44.2], "cu" => [23.1, -82.4], "ec" => [-0.2, -78.5],
  }.freeze

  # Full country name → code mapping
  COUNTRY_NAME_MAP = {
    "united states" => "us", "united kingdom" => "gb", "france" => "fr",
    "germany" => "de", "italy" => "it", "spain" => "es", "canada" => "ca",
    "australia" => "au", "india" => "in", "china" => "cn", "japan" => "jp",
    "south korea" => "kr", "brazil" => "br", "mexico" => "mx", "russia" => "ru",
    "turkey" => "tr", "israel" => "il", "ukraine" => "ua", "poland" => "pl",
    "netherlands" => "nl", "belgium" => "be", "switzerland" => "ch",
    "austria" => "at", "sweden" => "se", "norway" => "no", "denmark" => "dk",
    "finland" => "fi", "ireland" => "ie", "portugal" => "pt", "greece" => "gr",
    "romania" => "ro", "hungary" => "hu", "czech republic" => "cz",
    "egypt" => "eg", "south africa" => "za", "nigeria" => "ng",
    "saudi arabia" => "sa", "iran" => "ir", "iraq" => "iq",
    "united arab emirates" => "ae", "pakistan" => "pk", "indonesia" => "id",
    "thailand" => "th", "vietnam" => "vn", "philippines" => "ph",
    "malaysia" => "my", "singapore" => "sg", "new zealand" => "nz",
    "argentina" => "ar", "colombia" => "co", "chile" => "cl", "peru" => "pe",
    "taiwan" => "tw", "hong kong" => "hk", "syria" => "sy", "yemen" => "ye",
    "afghanistan" => "af", "myanmar" => "mm", "libya" => "ly", "sudan" => "sd",
    "cuba" => "cu", "ecuador" => "ec", "venezuela" => "ve",
  }.freeze

  # Words that map to countries (for title-based geocoding)
  TITLE_GEO_MAP = COUNTRY_NAME_MAP.merge(
    # Government/institutions
    "washington" => "us", "pentagon" => "us", "white house" => "us",
    "congress" => "us", "senate" => "us", "fcc" => "us", "fbi" => "us",
    "cia" => "us", "nsa" => "us", "doj" => "us",
    "moscow" => "ru", "kremlin" => "ru",
    "beijing" => "cn", "shanghai" => "cn", "shenzhen" => "cn",
    "tokyo" => "jp", "berlin" => "de", "paris" => "fr",
    "london" => "gb", "rome" => "it", "madrid" => "es",
    "kiev" => "ua", "kyiv" => "ua",
    "tehran" => "ir", "baghdad" => "iq", "kabul" => "af",
    "damascus" => "sy", "istanbul" => "tr", "cairo" => "eg",
    "mumbai" => "in", "delhi" => "in", "bangalore" => "in",
    "jerusalem" => "il", "gaza" => "il", "west bank" => "il",
    "nato" => "be", "eu" => "be", "european union" => "be",
    # Tech hubs
    "silicon valley" => "us", "san francisco" => "us", "new york" => "us",
    "seattle" => "us", "austin" => "us", "boston" => "us", "los angeles" => "us",
    "toronto" => "ca", "amsterdam" => "nl", "stockholm" => "se",
    "tel aviv" => "il", "dublin" => "ie", "zurich" => "ch",
    "singapore" => "sg", "seoul" => "kr", "taipei" => "tw",
    "bengaluru" => "in", "hyderabad" => "in",
    # Companies as proxy
    "google" => "us", "apple" => "us", "microsoft" => "us", "amazon" => "us",
    "meta" => "us", "openai" => "us", "anthropic" => "us", "nvidia" => "us",
    "tesla" => "us", "spacex" => "us",
  ).freeze

  TITLE_GEO_PATTERNS = TITLE_GEO_MAP.keys.sort_by { |k| -k.length }.freeze

  REFRESH_INTERVAL = 30.minutes

  class << self
    def refresh_if_stale(force: false)
      return 0 if !force && !stale?
      new.refresh_all
    end

    def stale?
      last = Rails.cache.read("multi_news_last_fetch")
      last.nil? || last < REFRESH_INTERVAL.ago
    end
  end

  def refresh_all
    all_records = []

    all_records.concat(fetch_worldnews)
    all_records.concat(fetch_currents)
    all_records.concat(fetch_thenewsapi)
    all_records.concat(fetch_gnews)
    all_records.concat(fetch_mediastack)
    all_records.concat(fetch_hackernews)

    return 0 if all_records.empty?

    # Dedup against existing DB records by URL
    existing_urls = NewsEvent.where(url: all_records.map { |r| r[:url] }).pluck(:url).to_set
    new_records = all_records.reject { |r| existing_urls.include?(r[:url]) }

    # Cross-source dedup by normalized title similarity
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
    end

    Rails.cache.write("multi_news_last_fetch", Time.current)
    new_records.size
  rescue => e
    Rails.logger.error("MultiNewsService: #{e.message}")
    0
  end

  private

  # ── WorldNewsAPI ──────────────────────────────────────────────
  # 50 points/day, 1 req/s. Search = 1 + 0.01/result. ~2 pts for 100 results.
  def fetch_worldnews
    key = ENV["WORLDNEWS_API_KEY"]
    return [] if key.blank?

    uri = URI("https://api.worldnewsapi.com/search-news")
    uri.query = URI.encode_www_form(
      "api-key" => key,
      "language" => "en",
      "sort" => "publish-time",
      "sort-direction" => "DESC",
      "number" => 100,
      "earliest-publish-date" => 24.hours.ago.strftime("%Y-%m-%d %H:%M:%S"),
    )

    data = fetch_json(uri)
    return [] unless data && data["news"]

    data["news"].filter_map do |article|
      lat, lng = resolve_location(article["source_country"], article["title"])
      next unless lat && lng

      build_record(
        url: article["url"],
        title: article["title"],
        name: article["source_country"] || article["author"],
        lat: lat, lng: lng,
        tone: sentiment_to_tone(article["sentiment"]),
        published_at: parse_time(article["publish_date"]),
        themes: extract_keywords(article["title"], article["text"]),
        source: "worldnews",
      )
    end
  rescue => e
    Rails.logger.error("MultiNewsService[worldnews]: #{e.message}")
    []
  end

  # ── Currents API ──────────────────────────────────────────────
  # 1000 req/day. Returns country as array of full names.
  def fetch_currents
    key = ENV["CURRENTS_API_KEY"]
    return [] if key.blank?

    uri = URI("https://api.currentsapi.services/v1/latest-news")
    uri.query = URI.encode_www_form(
      apiKey: key,
      language: "en",
      page_size: 100,
    )

    data = fetch_json(uri)
    return [] unless data && data["news"]

    data["news"].filter_map do |article|
      countries = article["country"]
      country_name = countries.is_a?(Array) ? countries.first : countries
      lat, lng = resolve_location(country_name, article["title"])
      next unless lat && lng

      build_record(
        url: article["url"],
        title: article["title"],
        name: country_name || article["author"],
        lat: lat, lng: lng,
        tone: 0.0,
        published_at: parse_time(article["published"]),
        themes: (article["category"] || []).first(5),
        source: "currents",
      )
    end
  rescue => e
    Rails.logger.error("MultiNewsService[currents]: #{e.message}")
    []
  end

  # ── TheNewsAPI ────────────────────────────────────────────────
  # Free tier, rate limited. locale is often nil on free tier.
  def fetch_thenewsapi
    key = ENV["THENEWSAPI_API_KEY"]
    return [] if key.blank?

    uri = URI("https://api.thenewsapi.com/v1/news/all")
    uri.query = URI.encode_www_form(
      api_token: key,
      language: "en",
      limit: 50,
      sort: "published_at",
    )

    data = fetch_json(uri)
    return [] unless data && data["data"]

    data["data"].filter_map do |article|
      lat, lng = resolve_location(article["locale"], article["title"])
      next unless lat && lng

      build_record(
        url: article["url"],
        title: article["title"],
        name: article["source"],
        lat: lat, lng: lng,
        tone: 0.0,
        published_at: parse_time(article["published_at"]),
        themes: (article["categories"] || []).first(5),
        source: "thenewsapi",
      )
    end
  rescue => e
    Rails.logger.error("MultiNewsService[thenewsapi]: #{e.message}")
    []
  end

  # ── GNews ─────────────────────────────────────────────────────
  # 100 req/day, max 10 articles/req. No geo data at all.
  def fetch_gnews
    key = ENV["GNEWS_API_KEY"]
    return [] if key.blank?

    uri = URI("https://gnews.io/api/v4/top-headlines")
    uri.query = URI.encode_www_form(
      apikey: key,
      lang: "en",
      max: 10,
      sortby: "publishedAt",
    )

    data = fetch_json(uri)
    return [] unless data && data["articles"]

    data["articles"].filter_map do |article|
      lat, lng = resolve_location(nil, article["title"])
      next unless lat && lng

      build_record(
        url: article["url"],
        title: article["title"],
        name: article.dig("source", "name"),
        lat: lat, lng: lng,
        tone: 0.0,
        published_at: parse_time(article["publishedAt"]),
        themes: [],
        source: "gnews",
      )
    end
  rescue => e
    Rails.logger.error("MultiNewsService[gnews]: #{e.message}")
    []
  end

  # ── Mediastack ────────────────────────────────────────────────
  # ~500 req/month. Free = HTTP only. Returns country code.
  def fetch_mediastack
    key = ENV["MEDIASTACK_API_KEY"]
    return [] if key.blank?

    uri = URI("http://api.mediastack.com/v1/news")
    uri.query = URI.encode_www_form(
      access_key: key,
      languages: "en",
      limit: 50,
      sort: "published_desc",
    )

    data = fetch_json(uri)
    return [] unless data && data["data"]

    data["data"].filter_map do |article|
      lat, lng = resolve_location(article["country"], article["title"])
      next unless lat && lng

      build_record(
        url: article["url"],
        title: article["title"],
        name: article["source"],
        lat: lat, lng: lng,
        tone: 0.0,
        published_at: parse_time(article["published_at"]),
        themes: (article["category"]&.split(",") || []).first(5),
        source: "mediastack",
      )
    end
  rescue => e
    Rails.logger.error("MultiNewsService[mediastack]: #{e.message}")
    []
  end

  # ── Hacker News (Algolia) ──────────────────────────────────────
  # No key needed, no rate limit. Title-based geocoding only.
  def fetch_hackernews
    uri = URI("https://hn.algolia.com/api/v1/search")
    uri.query = URI.encode_www_form(
      tags: "story",
      hitsPerPage: 50,
      numericFilters: "points>20",
    )

    data = fetch_json(uri)
    return [] unless data && data["hits"]

    data["hits"].filter_map do |hit|
      next if hit["url"].blank?

      lat, lng = resolve_location(nil, hit["title"])
      next unless lat && lng

      build_record(
        url: hit["url"],
        title: hit["title"],
        name: "Hacker News (#{hit["points"]} pts)",
        lat: lat, lng: lng,
        tone: 0.0,
        published_at: parse_time(hit["created_at"]),
        themes: hit["_tags"]&.select { |t| t.start_with?("story") } || [],
        source: "hackernews",
      )
    end
  rescue => e
    Rails.logger.error("MultiNewsService[hackernews]: #{e.message}")
    []
  end

  # ── Geocoding ─────────────────────────────────────────────────

  # Try country code → country name → title extraction, with jitter
  def resolve_location(country_hint, title)
    lat, lng = geocode_country(country_hint) ||
               geocode_country_name(country_hint) ||
               geocode_from_title(title)
    return nil unless lat && lng

    # Add jitter so same-country articles don't stack
    [lat + rand(-0.5..0.5), lng + rand(-0.5..0.5)]
  end

  def geocode_country(code)
    return nil if code.blank?
    COUNTRY_COORDS[code.to_s.downcase.strip]
  end

  def geocode_country_name(name)
    return nil if name.blank?
    lower = name.to_s.downcase.strip
    code = COUNTRY_NAME_MAP[lower]
    return COUNTRY_COORDS[code] if code
    # Partial match
    COUNTRY_NAME_MAP.each { |n, c| return COUNTRY_COORDS[c] if lower.include?(n) }
    nil
  end

  def geocode_from_title(title)
    return nil if title.blank?
    lower = title.downcase
    TITLE_GEO_PATTERNS.each do |pattern|
      if lower.include?(pattern)
        code = TITLE_GEO_MAP[pattern]
        return COUNTRY_COORDS[code] if code
      end
    end
    nil
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
      level: tone_level(tone_val),
      category: categorize_title(title),
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

  def sentiment_to_tone(sentiment)
    return 0.0 if sentiment.nil?
    (sentiment.to_f * 10).round(1)
  end

  def tone_level(tone)
    if tone <= -5 then "critical"
    elsif tone <= -2 then "negative"
    elsif tone <= 2 then "neutral"
    else "positive"
    end
  end

  CONFLICT_WORDS = %w[war attack military bomb strike kill soldier troops missile drone weapon conflict battle terror].freeze
  UNREST_WORDS = %w[protest rally march riot coup rebellion uprising demonstration].freeze
  DISASTER_WORDS = %w[earthquake flood hurricane tornado wildfire volcano tsunami cyclone storm].freeze
  HEALTH_WORDS = %w[pandemic virus outbreak epidemic vaccine hospital health disease infection].freeze
  ECONOMY_WORDS = %w[economy stock market inflation recession trade tariff gdp unemployment].freeze
  DIPLOMACY_WORDS = %w[peace ceasefire treaty summit diplomacy negotiate sanction].freeze

  def categorize_title(title)
    return "other" if title.blank?
    lower = title.downcase
    return "conflict" if CONFLICT_WORDS.any? { |w| lower.include?(w) }
    return "unrest" if UNREST_WORDS.any? { |w| lower.include?(w) }
    return "disaster" if DISASTER_WORDS.any? { |w| lower.include?(w) }
    return "health" if HEALTH_WORDS.any? { |w| lower.include?(w) }
    return "economy" if ECONOMY_WORDS.any? { |w| lower.include?(w) }
    return "diplomacy" if DIPLOMACY_WORDS.any? { |w| lower.include?(w) }
    "other"
  end

  def extract_keywords(title, text)
    combined = "#{title} #{text&.to_s&.first(500)}"
    all_words = CONFLICT_WORDS + UNREST_WORDS + DISASTER_WORDS + HEALTH_WORDS + ECONOMY_WORDS + DIPLOMACY_WORDS
    lower = combined.downcase
    all_words.select { |w| lower.include?(w) }.first(5)
  end

  # Dedup records by normalized title similarity (Jaccard on word sets)
  def dedup_by_title(records)
    seen = []
    records.select do |record|
      title = record[:title]
      if title.blank?
        true
      else
        words = normalize_title(title)
        duplicate = seen.any? { |s| jaccard(s, words) > 0.6 }
        seen << words unless duplicate
        !duplicate
      end
    end
  end

  def normalize_title(title)
    title.downcase.gsub(/[^a-z0-9\s]/, "").split.reject { |w| w.length < 3 }.to_set
  end

  def jaccard(set_a, set_b)
    return 0.0 if set_a.empty? || set_b.empty?
    intersection = (set_a & set_b).size.to_f
    union = (set_a | set_b).size.to_f
    intersection / union
  end
end
