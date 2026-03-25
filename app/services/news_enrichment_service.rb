require "net/http"
require "json"

class NewsEnrichmentService
  BATCH_SIZE = 50
  GEOCODE_MODEL = "gpt-4.1-nano"
  CLAUDE_MODEL = "claude-haiku-4-5-20251001"

  class << self
    def enrich_recent(limit: 200)
      # Find articles that haven't been AI-enriched yet
      # Skip articles that failed enrichment in the last hour (avoid hammering a down API)
      articles = NewsEvent.where(ai_enriched: [nil, false])
        .where("published_at > ?", 48.hours.ago)
        .order(published_at: :desc)
        .limit(limit)

      return 0 if articles.empty?

      # Check if any AI provider is available
      openai_ok = ENV["OPENAI_API_KEY"].present?
      claude_ok = ENV["ANTHROPIC_API_KEY"].present?

      unless openai_ok || claude_ok
        Rails.logger.info("NewsEnrichmentService: no AI API keys configured, skipping")
        return 0
      end

      total = 0
      articles.each_slice(BATCH_SIZE) do |batch|
        # Try OpenAI first, fall back to Claude
        if openai_ok
          combined_enrich(batch, :openai)
        elsif claude_ok
          combined_enrich(batch, :claude)
        end
        total += batch.size
      end

      Rails.logger.info("NewsEnrichmentService: enriched #{total} articles")
      total
    rescue => e
      Rails.logger.error("NewsEnrichmentService: #{e.message}")
      0
    end

    private

    # ── Combined: geocode + classify in one call ────────────────

    def combined_enrich(articles, provider)
      headlines = articles.map.with_index do |a, i|
        "#{i + 1}. #{a.title&.truncate(120)}"
      end.join("\n")

      prompt = <<~PROMPT
        For each headline, determine:
        1. The PHYSICAL LOCATION where the event occurred (not the news source location)
        2. The category

        Return JSON array: [{"i": 1, "city": "Baghdad", "country": "Iraq", "cat": "conflict"}, ...]

        Categories: conflict, terror, disaster, political, economic, health, science, sports, other
        For city: use the most specific known city name only if the headline supports it.
        For country: use the standard English country name only if the headline supports it.
        If the location is unclear from the headline, return null for city and/or country.

        Only return the JSON array, no other text.

        #{headlines}
      PROMPT

      data = if provider == :openai
        openai_chat(ENV["OPENAI_API_KEY"], prompt)
      else
        claude_message(ENV["ANTHROPIC_API_KEY"], prompt)
      end

      return unless data

      results = parse_json_array(data)
      return unless results

      results.each do |r|
        idx = (r["i"] || r["index"]).to_i - 1
        article = articles[idx]
        next unless article

        updates = { ai_enriched: true }

        # Location
        city = r["city"]&.strip
        country = r["country"]&.strip
        lat, lng = resolve_ai_location(city, country)
        if lat && lng
          updates[:latitude] = lat
          updates[:longitude] = lng
        end

        # Category — always update if valid (even without location fix)
        cat = r["cat"]&.strip&.downcase
        if cat.present? && %w[conflict terror disaster political economic health science sports other].include?(cat)
          updates[:category] = cat
        end

        article.update_columns(updates)
      end

      # Mark remaining articles as enriched (even if AI didn't return data for them)
      articles.each { |a| a.update_columns(ai_enriched: true) unless a.reload.ai_enriched? }
    rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED => e
      # Network error — leave articles unenriched so they get retried next cycle
      Rails.logger.warn("NewsEnrichmentService network error (will retry): #{e.message}")
    rescue => e
      # Other error — mark as enriched to prevent infinite retry on bad data
      Rails.logger.warn("NewsEnrichmentService combined_enrich error: #{e.message}")
      articles.each { |a| a.update_columns(ai_enriched: true) rescue nil }
    end

    # ── API clients ────────────────────────────────────────────

    def openai_chat(api_key, prompt)
      uri = URI("https://api.openai.com/v1/chat/completions")
      body = {
        model: GEOCODE_MODEL,
        messages: [{ role: "user", content: prompt }],
        temperature: 0.1,
        max_tokens: 2000,
      }

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 15
      http.read_timeout = 30

      req = Net::HTTP::Post.new(uri)
      req["Authorization"] = "Bearer #{api_key}"
      req["Content-Type"] = "application/json"
      req.body = body.to_json

      resp = http.request(req)
      unless resp.is_a?(Net::HTTPSuccess)
        Rails.logger.warn("OpenAI API error: #{resp.code} #{resp.body[0..200]}")
        return nil
      end

      result = JSON.parse(resp.body)
      result.dig("choices", 0, "message", "content")
    rescue => e
      Rails.logger.warn("OpenAI API error: #{e.message}")
      nil
    end

    def claude_message(api_key, prompt)
      uri = URI("https://api.anthropic.com/v1/messages")
      body = {
        model: CLAUDE_MODEL,
        max_tokens: 2000,
        messages: [{ role: "user", content: prompt }],
      }

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 15
      http.read_timeout = 30

      req = Net::HTTP::Post.new(uri)
      req["x-api-key"] = api_key
      req["anthropic-version"] = "2023-06-01"
      req["Content-Type"] = "application/json"
      req.body = body.to_json

      resp = http.request(req)
      unless resp.is_a?(Net::HTTPSuccess)
        Rails.logger.warn("Claude API error: #{resp.code} #{resp.body[0..200]}")
        return nil
      end

      result = JSON.parse(resp.body)
      content = result.dig("content", 0, "text")
      content
    rescue => e
      Rails.logger.warn("Claude API error: #{e.message}")
      nil
    end

    # ── Helpers ────────────────────────────────────────────────

    def parse_json_array(text)
      return nil if text.blank?
      # Extract JSON array from response (might have markdown fences)
      json_str = text[/\[.*\]/m]
      return nil unless json_str
      JSON.parse(json_str)
    rescue JSON::ParserError => e
      Rails.logger.warn("NewsEnrichmentService JSON parse error: #{e.message}")
      nil
    end

    # Extra locations the AI might return that aren't in our standard lookups
    EXTRA_LOCATIONS = {
      "west bank" => [31.95, 35.30], "occupied west bank" => [31.95, 35.30],
      "palestinian territories" => [31.50, 34.47], "palestine" => [31.50, 34.47],
      "kurdistan" => [36.19, 44.01], "iraqi kurdistan" => [36.19, 44.01],
      "crimea" => [44.95, 34.10], "donbas" => [48.00, 37.80],
      "sahel" => [14.0, 0.0], "horn of africa" => [8.0, 45.0],
      "strait of hormuz" => [26.5, 56.3], "red sea" => [20.0, 38.0],
      "south china sea" => [12.0, 114.0], "black sea" => [43.5, 34.0],
      "persian gulf" => [26.0, 52.0], "mediterranean" => [35.0, 18.0],
    }.freeze

    def resolve_ai_location(city, country)
      return nil if city&.downcase == "unspecified" && country&.downcase == "unspecified"

      # Try airport/landmark lookup first (most precise)
      if city.present? && city.downcase != "unspecified"
        coords = lookup_airport(city)
        return coords if coords
      end

      # Try city (reuse existing geocoding data)
      if city.present? && city.downcase != "unspecified"
        coords = NewsGeocodable::CITY_COORDS[city.downcase]
        return coords if coords
        coords = EXTRA_LOCATIONS[city.downcase]
        return coords if coords
      end

      # Try country
      if country.present? && country.downcase != "unspecified"
        code = NewsGeocodable::COUNTRY_NAME_MAP[country.downcase]
        code ||= country.downcase if country.length == 2
        coords = NewsGeocodable::COUNTRY_COORDS[code]
        return coords if coords
        # Try extra locations
        coords = EXTRA_LOCATIONS[country.downcase]
        return coords if coords
      end

      # Last resort: Nominatim geocoding (cached, rate-limited)
      query = [city, country].compact.reject { |s| s.downcase == "unspecified" }.join(", ")
      if query.present?
        coords = nominatim_lookup(query)
        return coords if coords
      end

      nil
    end

    # Nominatim (OpenStreetMap) geocoding — only called for locations
    # not in our hardcoded lists. Results cached in Rails.cache for 30 days
    # so each unique location is only looked up once.
    def nominatim_lookup(query)
      return nil if query.blank? || query.length < 3

      cache_key = "nominatim:#{query.downcase.strip}"
      cached = Rails.cache.read(cache_key)
      return nil if cached == :miss  # previously failed lookup
      return cached if cached        # [lat, lng] from previous success

      # Rate limit: track last request time to enforce 1 req/sec
      last_req = Rails.cache.read("nominatim:last_request_at")
      if last_req && (Time.current - last_req) < 1.2
        sleep(1.2 - (Time.current - last_req))
      end

      uri = URI("https://nominatim.openstreetmap.org/search")
      uri.query = URI.encode_www_form(q: query, format: "json", limit: 1)
      req = Net::HTTP::Get.new(uri)
      req["User-Agent"] = "GlobeTracker/1.0 (news geocoding)"

      resp = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true,
                             open_timeout: 5, read_timeout: 5) { |h| h.request(req) }
      Rails.cache.write("nominatim:last_request_at", Time.current)

      if resp.is_a?(Net::HTTPSuccess)
        results = JSON.parse(resp.body)
        if results.any?
          lat = results[0]["lat"].to_f
          lng = results[0]["lon"].to_f
          coords = [lat, lng]
          Rails.cache.write(cache_key, coords, expires_in: 30.days)
          Rails.logger.info("Nominatim: '#{query}' → [#{lat}, #{lng}]")
          return coords
        end
      end

      # Cache misses too so we don't re-query failed lookups
      Rails.cache.write(cache_key, :miss, expires_in: 7.days)
      nil
    rescue => e
      Rails.logger.warn("Nominatim lookup failed for '#{query}': #{e.message}")
      nil
    end

    # Match city name against airport database for precise coordinates
    def lookup_airport(name)
      @airport_cache ||= build_airport_cache
      @airport_cache[name.downcase]
    end

    def build_airport_cache
      cache = {}
      return cache unless defined?(Airport) && Airport.table_exists?

      Airport.where.not(latitude: nil, longitude: nil).find_each do |ap|
        full = ap.name&.downcase
        next unless full

        # Index by full name: "LaGuardia Airport" → [lat, lng]
        cache[full] = [ap.latitude, ap.longitude]

        # Index by short name: "LaGuardia" (without "Airport", "International", etc.)
        short = full.gsub(/\s*(international|airport|regional|municipal|air base|airbase|afb)\s*/i, "").strip
        cache[short] = [ap.latitude, ap.longitude] if short.length > 3

        # Index by ICAO/IATA codes
        cache[ap.icao_code&.downcase] = [ap.latitude, ap.longitude] if ap.icao_code.present?
        cache[ap.iata_code&.downcase] = [ap.latitude, ap.longitude] if ap.respond_to?(:iata_code) && ap.iata_code.present?
      end

      Rails.logger.info("NewsEnrichmentService: built airport cache with #{cache.size} entries")
      cache
    end
  end
end
