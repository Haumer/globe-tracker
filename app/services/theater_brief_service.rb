require "digest"
require "json"
require "net/http"

class TheaterBriefService
  SNAPSHOT_TYPE = "theater_brief".freeze
  OPENAI_MODEL = "gpt-4.1-nano".freeze
  CLAUDE_MODEL = "claude-sonnet-4-20250514".freeze
  MAX_TOKENS = 1200
  ENQUEUE_TTL = 5.minutes
  FAILURE_TTL = 30.minutes

  class << self
    def fetch_or_enqueue(theater:, cell_key: nil)
      zone = resolve_zone(theater:, cell_key:)
      return nil unless zone

      scope_key = scope_key_for(zone)
      snapshot = LayerSnapshot.find_by(snapshot_type: SNAPSHOT_TYPE, scope_key: scope_key)
      return snapshot_payload(snapshot, zone, scope_key) if snapshot&.status == "ready"
      return snapshot_payload(snapshot, zone, scope_key) if snapshot&.fresh?

      snapshot = mark_pending(scope_key:, zone:)
      enqueue_refresh(scope_key:, zone:)
      snapshot_payload(snapshot, zone, scope_key)
    end

    def refresh(scope_key:, zone_payload:, force: false)
      zone = normalize_zone(zone_payload)
      snapshot = LayerSnapshot.find_or_initialize_by(snapshot_type: SNAPSHOT_TYPE, scope_key: scope_key.to_s)
      return snapshot if snapshot.persisted? && snapshot.status == "ready" && !force

      brief = generate_brief_payload(zone)
      snapshot.assign_attributes(
        status: "ready",
        error_code: nil,
        payload: { brief: brief.except(:provider, :model) },
        metadata: snapshot_metadata(zone, provider: brief[:provider], model: brief[:model]),
        fetched_at: Time.current,
        expires_at: nil,
      )
      snapshot.save!
      snapshot
    rescue StandardError => e
      snapshot ||= LayerSnapshot.find_or_initialize_by(snapshot_type: SNAPSHOT_TYPE, scope_key: scope_key.to_s)
      snapshot.assign_attributes(
        status: "error",
        error_code: "#{e.class}: #{e.message}".first(255),
        payload: snapshot.payload.presence || {},
        metadata: snapshot_metadata(zone || {}, provider: nil, model: nil),
        fetched_at: Time.current,
        expires_at: Time.current + FAILURE_TTL,
      )
      snapshot.save!
      raise
    end

    def scope_key_for(zone_payload)
      zone = normalize_zone(zone_payload)
      slug = slugify(zone[:theater] || zone[:situation_name] || zone[:cell_key] || "theater")
      digest = Digest::SHA256.hexdigest(JSON.generate(zone_signature(zone)))[0, 16]
      "#{slug}:#{digest}"
    end

    private

    def resolve_zone(theater:, cell_key: nil)
      snapshot = ConflictPulseSnapshotService.fetch_or_enqueue
      payload = snapshot&.payload.presence || {}
      zones = Array(payload["zones"] || payload[:zones]).map { |zone| normalize_zone(zone) }
      return nil if zones.empty?

      if cell_key.present?
        matched = zones.find { |zone| zone[:cell_key].to_s == cell_key.to_s }
        return matched if matched
      end

      raw = theater.to_s.strip
      return nil if raw.blank?

      zones
        .select { |zone| zone[:theater].to_s.casecmp?(raw) }
        .max_by { |zone| [zone[:pulse_score].to_i, zone[:count_24h].to_i, zone[:source_count].to_i] }
    end

    def normalize_zone(zone_payload)
      zone_payload.to_h.deep_symbolize_keys
    end

    def mark_pending(scope_key:, zone:)
      snapshot = LayerSnapshot.find_or_initialize_by(snapshot_type: SNAPSHOT_TYPE, scope_key: scope_key)
      snapshot.assign_attributes(
        status: "pending",
        error_code: nil,
        payload: snapshot.payload.presence || {},
        metadata: snapshot_metadata(zone, provider: nil, model: nil),
        fetched_at: Time.current,
        expires_at: Time.current + ENQUEUE_TTL,
      )
      snapshot.save!
      snapshot
    end

    def enqueue_refresh(scope_key:, zone:)
      BackgroundRefreshScheduler.enqueue_once(
        GenerateTheaterBriefJob,
        scope_key,
        zone.deep_stringify_keys,
        key: "theater-brief:#{scope_key}",
        ttl: ENQUEUE_TTL,
      )
    end

    def snapshot_payload(snapshot, zone, scope_key)
      {
        status: snapshot_status(snapshot),
        scope_key: scope_key,
        brief: snapshot&.payload&.dig("brief"),
        generated_at: snapshot&.fetched_at&.iso8601,
        provider: snapshot&.metadata&.dig("provider"),
        model: snapshot&.metadata&.dig("model"),
        error: snapshot&.error_code,
        source_context: snapshot_metadata(zone, provider: nil, model: nil).fetch("source_context"),
      }
    end

    def snapshot_status(snapshot)
      return "pending" unless snapshot
      return "ready" if snapshot.status == "ready"

      snapshot.status
    end

    def snapshot_metadata(zone, provider:, model:)
      {
        theater: zone[:theater],
        cell_key: zone[:cell_key],
        provider: provider,
        model: model,
        source_context: {
          theater: zone[:theater],
          situation_name: zone[:situation_name],
          pulse_score: zone[:pulse_score],
          escalation_trend: zone[:escalation_trend],
          reports_24h: zone[:count_24h],
          sources: zone[:source_count],
          stories: zone[:story_count],
          spike_ratio: zone[:spike_ratio],
          corroborating_signals: Array(zone[:cross_layer_signals]).size,
          detected_at: zone[:detected_at],
        }.compact,
      }.deep_stringify_keys
    end

    def zone_signature(zone)
      {
        theater: zone[:theater].to_s,
        cell_key: zone[:cell_key].to_s,
        situation_name: zone[:situation_name].to_s,
        pulse_score: zone[:pulse_score].to_i,
        escalation_trend: zone[:escalation_trend].to_s,
        count_24h: zone[:count_24h].to_i,
        source_count: zone[:source_count].to_i,
        story_count: zone[:story_count].to_i,
        spike_ratio: zone[:spike_ratio].to_f.round(2),
        signals: (zone[:cross_layer_signals] || {}).to_h.transform_keys(&:to_s).sort.to_h,
        headlines: Array(zone[:top_articles]).first(4).map do |article|
          {
            title: article[:title].to_s,
            publisher: article[:publisher].to_s,
            published_at: article[:published_at].to_s,
          }
        end,
      }
    end

    def build_prompt(zone)
      top_articles = Array(zone[:top_articles]).first(4).map do |article|
        publisher = article[:publisher].presence || article[:source].presence || "unknown source"
        published = article[:published_at].presence || "unknown time"
        "- #{article[:title]} (#{publisher}; #{published})"
      end
      signal_lines = (zone[:cross_layer_signals] || {}).map { |key, value| "- #{key.to_s.tr('_', ' ')}: #{value}" }

      <<~PROMPT
        You are writing a saved operational brief for a single conflict theater in GlobeTracker.

        Return strict JSON only with this shape:
        {
          "assessment": "2-3 sentence assessment grounded only in the provided data",
          "why_we_believe_it": ["short evidence point", "short evidence point", "short evidence point"],
          "key_developments": ["short bullet", "short bullet", "short bullet"],
          "watch_next": ["short watch item", "short watch item", "short watch item"],
          "confidence_level": "high|medium|low",
          "confidence_rationale": "one short sentence explaining confidence"
        }

        Rules:
        - Do not invent actors, casualties, or intent not supported below.
        - Keep language terse and analytical, not dramatic.
        - Mention uncertainty when evidence is limited.
        - Each array item should be a single sentence fragment or short sentence.
        - "assessment" must answer what is happening right now, not restate the title.
        - "why_we_believe_it" must cite the concrete basis for the read: reporting density, source depth, spike behavior, corroborating layers, or specific reporting.
        - No markdown, no prose outside JSON.

        THEATER
        Name: #{zone[:theater] || "Unattributed theater"}
        Situation: #{zone[:situation_name] || "Developing situation"}
        Pulse score: #{zone[:pulse_score] || 0}
        Trend: #{zone[:escalation_trend] || "unknown"}
        Reports / 24h: #{zone[:count_24h] || 0}
        Sources: #{zone[:source_count] || 0}
        Story clusters: #{zone[:story_count] || 0}
        Spike ratio: #{zone[:spike_ratio] || 0}x
        Average tone: #{zone[:avg_tone] || 0}
        Detected at: #{zone[:detected_at] || "unknown"}

        CORROBORATING SIGNALS
        #{signal_lines.any? ? signal_lines.join("\n") : "- none"}

        TOP REPORTING
        #{top_articles.any? ? top_articles.join("\n") : "- none"}
      PROMPT
    end

    def generate_brief_payload(zone)
      prompt = build_prompt(zone)
      openai_key = ENV["OPENAI_API_KEY"]
      anthropic_key = ENV["ANTHROPIC_API_KEY"]

      if openai_key.present?
        content = openai_message(openai_key, prompt)
        brief = parse_brief_payload(content)
        return brief.merge(provider: "openai", model: OPENAI_MODEL) if brief
      end

      if anthropic_key.present?
        content = claude_message(anthropic_key, prompt)
        brief = parse_brief_payload(content)
        return brief.merge(provider: "anthropic", model: CLAUDE_MODEL) if brief
      end

      raise "no configured AI provider produced a theater brief"
    end

    def openai_message(api_key, prompt)
      uri = URI("https://api.openai.com/v1/chat/completions")
      body = {
        model: OPENAI_MODEL,
        messages: [{ role: "user", content: prompt }],
        temperature: 0.2,
        max_tokens: MAX_TOKENS,
      }

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 20
      http.read_timeout = 45

      req = Net::HTTP::Post.new(uri)
      req["Authorization"] = "Bearer #{api_key}"
      req["Content-Type"] = "application/json"
      req.body = body.to_json

      resp = http.request(req)
      unless resp.is_a?(Net::HTTPSuccess)
        Rails.logger.warn("TheaterBriefService OpenAI error: #{resp.code} #{resp.body.to_s[0..200]}")
        return nil
      end

      JSON.parse(resp.body).dig("choices", 0, "message", "content")
    rescue StandardError => e
      Rails.logger.warn("TheaterBriefService OpenAI error: #{e.message}")
      nil
    end

    def claude_message(api_key, prompt)
      uri = URI("https://api.anthropic.com/v1/messages")
      body = {
        model: CLAUDE_MODEL,
        max_tokens: MAX_TOKENS,
        messages: [{ role: "user", content: prompt }],
      }

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 20
      http.read_timeout = 45

      req = Net::HTTP::Post.new(uri)
      req["x-api-key"] = api_key
      req["anthropic-version"] = "2023-06-01"
      req["Content-Type"] = "application/json"
      req.body = body.to_json

      resp = http.request(req)
      unless resp.is_a?(Net::HTTPSuccess)
        Rails.logger.warn("TheaterBriefService Claude error: #{resp.code} #{resp.body.to_s[0..200]}")
        return nil
      end

      JSON.parse(resp.body).dig("content", 0, "text")
    rescue StandardError => e
      Rails.logger.warn("TheaterBriefService Claude error: #{e.message}")
      nil
    end

    def parse_brief_payload(text)
      return nil if text.blank?

      raw = text[/\{.*\}/m]
      return nil if raw.blank?

      json = JSON.parse(raw)
      {
        assessment: json["assessment"].to_s.strip,
        why_we_believe_it: normalize_sentence_list(json["why_we_believe_it"], limit: 4),
        key_developments: normalize_sentence_list(json["key_developments"], limit: 4),
        watch_next: normalize_sentence_list(json["watch_next"], limit: 4),
        confidence_level: normalize_confidence(json["confidence_level"]),
        confidence_rationale: json["confidence_rationale"].to_s.strip.presence,
      }
    rescue JSON::ParserError => e
      Rails.logger.warn("TheaterBriefService JSON parse error: #{e.message}")
      nil
    end

    def normalize_sentence_list(value, limit:)
      Array(value)
        .map { |entry| entry.to_s.squish }
        .reject(&:blank?)
        .first(limit)
    end

    def normalize_confidence(value)
      normalized = value.to_s.strip.downcase
      %w[high medium low].include?(normalized) ? normalized : "medium"
    end

    def slugify(value)
      value.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-+\z/, "").presence || "theater"
    end
  end
end
