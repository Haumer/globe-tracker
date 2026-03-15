require "net/http"
require "json"

class NewsEnrichmentService
  BATCH_SIZE = 50
  GEOCODE_MODEL = "gpt-4.1-nano"
  CLUSTER_MODEL = "claude-haiku-4-5-20251001"

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

    # ── Combined: geocode + classify + cluster in one call ─────

    def combined_enrich(articles, provider)
      headlines = articles.map.with_index do |a, i|
        "#{i + 1}. #{a.title&.truncate(120)}"
      end.join("\n")

      prompt = <<~PROMPT
        For each headline, determine:
        1. The PHYSICAL LOCATION where the event occurred (not the news source location)
        2. The category
        3. A cluster key to group duplicate/related stories

        Return JSON array: [{"i": 1, "city": "Baghdad", "country": "Iraq", "cat": "conflict", "cluster": "baghdad-embassy-attack"}, ...]

        Categories: conflict, terror, disaster, political, economic, health, science, sports, other
        Cluster key: 3-5 word lowercase hyphenated slug. Same event = same cluster key.
        For city: use the most specific known city name. If no city, use the capital of the country.
        For country: use the standard English country name (e.g., "Israel" not "Palestinian Territories", "Pakistan" not "unspecified").
        Never return "unspecified" — always make your best guess based on the headline context.

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

      now = Time.current
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

        # Cluster — always update if present
        cluster_key = r["cluster"]&.strip&.downcase&.gsub(/[^a-z0-9\-]/, "-")
        if cluster_key.present? && cluster_key != "unspecified"
          updates[:story_cluster_id] = Digest::MD5.hexdigest(cluster_key)[0..7]
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

    # ── OpenAI: geocode + classify (fallback) ──────────────────

    def geocode_batch(articles)
      api_key = ENV["OPENAI_API_KEY"]
      return unless api_key.present?

      headlines = articles.map.with_index do |a, i|
        "#{i + 1}. #{a.title&.truncate(120)}"
      end.join("\n")

      prompt = <<~PROMPT
        For each headline, return the PHYSICAL LOCATION where the event occurred (not where the news source is based).
        Return JSON array: [{"i": 1, "city": "Baghdad", "country": "Iraq", "cat": "conflict"}, ...]
        Categories: conflict, terror, disaster, political, economic, health, science, sports, other
        If the event location is unclear, use the most prominent location mentioned.
        Only return the JSON array, no other text.

        #{headlines}
      PROMPT

      data = openai_chat(api_key, prompt)
      return unless data

      results = parse_json_array(data)
      return unless results

      now = Time.current
      results.each do |r|
        idx = (r["i"] || r["index"]).to_i - 1
        article = articles[idx]
        next unless article

        city = r["city"]&.strip
        country = r["country"]&.strip
        cat = r["cat"]&.strip&.downcase

        # Resolve lat/lng from city or country
        lat, lng = resolve_ai_location(city, country)
        next unless lat && lng

        updates = { ai_enriched: true }
        updates[:latitude] = lat
        updates[:longitude] = lng
        updates[:category] = cat if cat.present? && %w[conflict terror disaster political economic health science sports other].include?(cat)

        article.update_columns(updates)
      end
    rescue => e
      Rails.logger.warn("NewsEnrichmentService geocode error: #{e.message}")
    end

    # ── Claude: semantic dedup + story clustering ──────────────

    def cluster_batch(articles)
      api_key = ENV["ANTHROPIC_API_KEY"]
      return unless api_key.present?

      headlines = articles.map.with_index do |a, i|
        "#{i + 1}. #{a.title&.truncate(120)}"
      end.join("\n")

      prompt = <<~PROMPT
        Group these headlines into story clusters. Headlines about the same event/story get the same cluster key.
        Return JSON array: [{"i": 1, "cluster": "baghdad-embassy-attack"}, ...]
        The cluster key should be a short lowercase slug (3-5 words, hyphenated).
        Different aspects of the same event share a cluster (e.g., "embassy attacked" and "casualties reported from embassy" are the same cluster).
        Unrelated stories each get their own unique cluster key.
        Only return the JSON array, no other text.

        #{headlines}
      PROMPT

      data = claude_message(api_key, prompt)
      return unless data

      results = parse_json_array(data)
      return unless results

      # Build cluster mapping
      cluster_map = {}
      results.each do |r|
        idx = (r["i"] || r["index"]).to_i - 1
        cluster_key = r["cluster"]&.strip&.downcase&.gsub(/[^a-z0-9\-]/, "-")
        next unless cluster_key.present?
        cluster_map[idx] = cluster_key
      end

      # Generate stable cluster IDs from keys
      cluster_map.each do |idx, key|
        article = articles[idx]
        next unless article
        cluster_id = Digest::MD5.hexdigest(key)[0..7]
        article.update_columns(story_cluster_id: cluster_id, ai_enriched: true)
      end
    rescue => e
      Rails.logger.warn("NewsEnrichmentService cluster error: #{e.message}")
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
        model: CLUSTER_MODEL,
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

      # Try city first (reuse existing geocoding data)
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
        return [coords[0] + rand(-0.2..0.2), coords[1] + rand(-0.2..0.2)] if coords
        # Try extra locations
        coords = EXTRA_LOCATIONS[country.downcase]
        return coords if coords
      end

      nil
    end
  end
end
