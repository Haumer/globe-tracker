class IntelligenceBriefService
  MODEL = "claude-sonnet-4-20250514"
  CACHE_KEY = "intelligence_brief"
  MAX_TOKENS = 4000

  class << self
    def generate(force: false)
      return Rails.cache.read(CACHE_KEY) if !force && Rails.cache.read(CACHE_KEY)

      api_key = ENV["ANTHROPIC_API_KEY"]
      unless api_key.present?
        Rails.logger.warn("IntelligenceBriefService: ANTHROPIC_API_KEY not set")
        return nil
      end

      context = gather_context
      prompt = build_prompt(context)
      brief = call_claude(api_key, prompt)
      return nil unless brief

      result = {
        brief: brief,
        generated_at: Time.current.iso8601,
        context_summary: {
          conflict_zones: context[:conflict_zones].size,
          earthquakes: context[:earthquakes].size,
          outages: context[:outages].size,
          fires: context[:fires],
          news_articles: context[:top_news].size,
          gps_jamming: context[:gps_jamming].size,
        },
      }

      Rails.cache.write(CACHE_KEY, result, expires_in: 6.hours)
      result
    end

    def invalidate
      Rails.cache.delete(CACHE_KEY)
    end

    private

    def gather_context
      {
        conflict_zones: gather_conflicts,
        earthquakes: gather_earthquakes,
        outages: gather_outages,
        fires: gather_fire_count,
        gps_jamming: gather_jamming,
        top_news: gather_news,
        commodities: gather_commodities,
        military_flights: gather_military_flights,
      }
    end

    def gather_conflicts
      data = ConflictPulseService.analyze
      (data[:zones] || []).sort_by { |z| -z[:pulse_score] }.first(10).map do |z|
        {
          situation: z[:situation_name] || z[:cell_key],
          theater: z[:theater],
          score: z[:pulse_score],
          trend: z[:escalation_trend],
          reports_24h: z[:count_24h],
          sources: z[:source_count],
          headlines: (z[:top_headlines] || []).first(3),
          tone: z[:avg_tone]&.round(1),
          spike: z[:spike_ratio]&.round(1),
        }
      end
    end

    def gather_earthquakes
      Earthquake.where("event_time > ?", 24.hours.ago)
                .where("magnitude >= ?", 4.0)
                .order(magnitude: :desc)
                .limit(10)
                .map { |q| { title: q.title, mag: q.magnitude, depth: q.depth, time: q.event_time&.iso8601 } }
    end

    def gather_outages
      InternetOutage.where("started_at > ?", 24.hours.ago)
                    .where(level: %w[critical major])
                    .order(score: :desc)
                    .limit(5)
                    .map { |o| { country: o.entity_name, level: o.level, score: o.score } }
    end

    def gather_fire_count
      FireHotspot.where("acq_datetime > ?", 24.hours.ago).count
    end

    def gather_jamming
      GpsJammingSnapshot.where("recorded_at > ?", 6.hours.ago)
                        .where(level: "high")
                        .select("DISTINCT ON (cell_lat, cell_lng) cell_lat, cell_lng, percentage, level")
                        .order("cell_lat, cell_lng, recorded_at DESC")
                        .limit(10)
                        .map { |s| { lat: s.cell_lat, lng: s.cell_lng, pct: s.percentage } }
    end

    def gather_news
      NewsEvent.where("published_at > ?", 12.hours.ago)
               .where("tone IS NOT NULL AND ABS(tone) >= 4")
               .order(Arel.sql("ABS(tone) DESC"))
               .limit(15)
               .pluck(:title, :tone, :category, :source)
               .map { |t, tone, cat, src| { title: t, tone: tone, category: cat, source: src } }
    end

    def gather_commodities
      CommodityPrice.select("DISTINCT ON (symbol) *")
                    .order(:symbol, recorded_at: :desc)
                    .limit(10)
                    .map { |p| { symbol: p.symbol, name: p.name, price: p.price.to_f, change: p.change_pct&.to_f } }
    end

    def gather_military_flights
      Flight.where(military: true).where("updated_at > ?", 30.minutes.ago).count
    end

    def build_prompt(ctx)
      <<~PROMPT
        You are a senior intelligence analyst writing a classified-style daily briefing for a global situational awareness platform called GlobeTracker. Write in a terse, authoritative voice — like a PDB (President's Daily Brief) or SITREP.

        Use this structure:
        1. CRITICAL — Situations requiring immediate attention (pulse score 70+, surging/escalating)
        2. HIGH — Active situations with significant developments
        3. NOTABLE — Emerging situations, notable events, or significant changes
        4. CROSS-LAYER CONNECTIONS — Patterns across different data types (conflict + infrastructure, earthquake + cables, military flights + jamming)
        5. MARKET IMPACT — How events affect commodities, shipping, connectivity

        Rules:
        - Be specific: name countries, cite numbers, quote headlines
        - Identify patterns humans would miss (e.g., "GPS jamming in eastern Med coincides with 14 military sorties and a submarine cable landing point")
        - Note what's CHANGED — escalation trends, new zones, declining situations
        - Keep each section 2-4 bullet points max
        - Use military/intelligence terminology where appropriate
        - Total length: 400-600 words
        - Do NOT use markdown headers — use plain text section labels like "CRITICAL" in caps

        Current data (#{Time.current.strftime("%Y-%m-%d %H:%M UTC")}):

        CONFLICT ZONES (#{ctx[:conflict_zones].size} active):
        #{ctx[:conflict_zones].map { |z| "- #{z[:situation]} (#{z[:theater] || 'unaffiliated'}): score=#{z[:score]}, trend=#{z[:trend]}, #{z[:reports_24h]} reports/24h, #{z[:sources]} sources, spike=#{z[:spike]}x, tone=#{z[:tone]}. Headlines: #{z[:headlines].join(' | ')}" }.join("\n")}

        SEISMIC (24h):
        #{ctx[:earthquakes].any? ? ctx[:earthquakes].map { |q| "- #{q[:title]} (M#{q[:mag]}, depth #{q[:depth]}km)" }.join("\n") : "No significant earthquakes."}

        INTERNET OUTAGES:
        #{ctx[:outages].any? ? ctx[:outages].map { |o| "- #{o[:country]}: #{o[:level]} (score #{o[:score]})" }.join("\n") : "No critical outages."}

        GPS JAMMING (high-level zones):
        #{ctx[:gps_jamming].any? ? ctx[:gps_jamming].map { |j| "- #{j[:lat].round(1)}°N, #{j[:lng].round(1)}°E: #{j[:pct]}% interference" }.join("\n") : "No significant jamming detected."}

        FIRE HOTSPOTS: #{ctx[:fires]} active in last 24h

        MILITARY FLIGHTS: #{ctx[:military_flights]} currently airborne

        COMMODITY PRICES:
        #{ctx[:commodities].map { |c| "- #{c[:name]}: $#{c[:price].round(2)}#{c[:change] ? " (#{c[:change] > 0 ? '+' : ''}#{c[:change].round(1)}%)" : ''}" }.join("\n")}

        HIGH-IMPACT NEWS (tone ≤-4 or ≥+4):
        #{ctx[:top_news].map { |n| "- [#{n[:category]}/#{n[:source]}] #{n[:title]} (tone: #{n[:tone]})" }.join("\n")}
      PROMPT
    end

    def call_claude(api_key, prompt)
      uri = URI("https://api.anthropic.com/v1/messages")
      body = {
        model: MODEL,
        max_tokens: MAX_TOKENS,
        messages: [{ role: "user", content: prompt }],
      }

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 30
      http.read_timeout = 60

      req = Net::HTTP::Post.new(uri)
      req["x-api-key"] = api_key
      req["anthropic-version"] = "2023-06-01"
      req["Content-Type"] = "application/json"
      req.body = body.to_json

      resp = http.request(req)
      unless resp.is_a?(Net::HTTPSuccess)
        Rails.logger.error("IntelligenceBriefService Claude error: #{resp.code} #{resp.body[0..300]}")
        return nil
      end

      result = JSON.parse(resp.body)
      result.dig("content", 0, "text")
    rescue => e
      Rails.logger.error("IntelligenceBriefService error: #{e.message}")
      nil
    end
  end
end
