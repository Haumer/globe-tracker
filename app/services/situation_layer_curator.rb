# Which optional overlays deserve to be on by default for one situation.
#
# The layer catalog is fixed and every layer is always available to toggle by
# hand -- this service only chooses the defaults. Two bases, reported so the
# client can say which one it is showing:
#
#   "ai"        -- the model read the situation (name, event types, headlines)
#                  and picked from the catalog. Same discipline as
#                  NewsClaimTypeResolver: it picks from a closed list, an
#                  unknown key is dropped, a failure never raises.
#   "heuristic" -- no model available (or it failed); rules keyed on the event
#                  types and the anchor entity pick instead.
#
# The result is cached: curation reads slow-moving facts about the situation,
# and a browser toggling layers should not bill an OpenAI call per click.
class SituationLayerCurator
  MODEL = ENV.fetch("LAYER_CURATOR_MODEL", "gpt-4.1-mini").freeze
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze
  OPEN_TIMEOUT = 10
  READ_TIMEOUT = 30
  MAX_PICKS = 6
  CACHE_TTL = 6.hours

  Result = Struct.new(:basis, :picks, keyword_init: true)

  def self.call(situation:, available_keys:, client: nil)
    new(situation: situation, available_keys: available_keys, client: client).call
  end

  def initialize(situation:, available_keys:, client: nil)
    @situation = situation
    @available_keys = available_keys
    @client = client
  end

  def call
    Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
      ai_result || heuristic_result
    end
  end

  private

  attr_reader :situation, :available_keys

  def cache_key
    fingerprint = [
      situation[:id],
      situation[:last_seen_at],
      situation[:member_count],
      available_keys.sort.join(",")
    ].join(":")
    "situation-layer-curation:v1:#{fingerprint}"
  end

  # ── model path ───────────────────────────────────────────────────────

  def ai_result
    client = @client || default_client
    return nil unless client

    content = client.call(system: system_prompt, user: user_prompt)
    picks = parse_picks(content)
    return nil if picks.nil?

    Result.new(basis: "ai", picks: picks)
  rescue StandardError => error
    Rails.logger.warn("[SituationLayerCurator] model call failed: #{error.class}: #{error.message}")
    nil
  end

  def default_client
    return nil if ENV["OPENAI_API_KEY"].blank?

    OpenAiChat.new
  end

  def system_prompt
    <<~PROMPT
      You choose which live data overlays belong on a globe view of one news
      situation. Pick only overlays that would genuinely inform this specific
      story -- an analyst glancing at the globe should see corroborating or
      contextual data, not decoration. Pick between 1 and #{MAX_PICKS}.
      Respond with JSON only: {"layers": [{"key": "...", "reason": "..."}]}.
      Each reason is one short sentence tied to this situation. Use only keys
      from the list given. If nothing beyond the baseline would help, respond
      {"layers": []}.
    PROMPT
  end

  def user_prompt
    types = situation[:members].to_a.filter_map { |m| m[:event_type] }.tally
      .sort_by { |_, count| -count }.first(6).map { |type, count| "#{type} x#{count}" }
    headlines = situation[:members].to_a.filter_map { |m| m[:headline] }.first(8)

    <<~PROMPT
      Situation: #{situation[:name]}
      Anchored on: #{situation.dig(:concerns, :entity_type) || "actor (no place of its own)"}
      Country: #{situation.dig(:concerns, :country_code) || "unknown"}
      Event types: #{types.join(", ").presence || "unknown"}
      Sample headlines:
      #{headlines.map { |h| "- #{h}" }.join("\n")}

      Available overlays:
      #{catalog_lines.join("\n")}
    PROMPT
  end

  def catalog_lines
    SituationLayerPlanService::CATALOG.filter_map do |layer|
      next if layer[:baseline]
      next unless available_keys.include?(layer[:key])

      "- #{layer[:key]}: #{layer[:meaning]}"
    end
  end

  def parse_picks(content)
    return nil if content.blank?

    json = content[/\{.*\}/m]
    return nil unless json

    rows = JSON.parse(json)["layers"]
    return nil unless rows.is_a?(Array)

    rows.first(MAX_PICKS).each_with_object({}) do |row, picks|
      key = row["key"].to_s
      next unless available_keys.include?(key)

      picks[key] = row["reason"].to_s.presence || "picked by the curator"
    end
  rescue JSON::ParserError
    nil
  end

  # ── rules path ───────────────────────────────────────────────────────

  def heuristic_result
    Result.new(basis: "heuristic", picks: heuristic_picks.first(MAX_PICKS).to_h)
  end

  def heuristic_picks
    picks = {}
    types = situation[:members].to_a.filter_map { |m| m[:event_type].to_s.downcase }
    names = [situation[:name], situation.dig(:concerns, :name)].compact.join(" ").downcase
    entity_type = situation.dig(:concerns, :entity_type).to_s

    conflict = types.any? { |t| t.match?(/strike|attack|clash|military|shell|drone|missile|offensive|combat|bomb|raid/) }
    quake = types.any? { |t| t.match?(/earthquake|quake|seismic/) } || names.match?(/earthquake|quake/)
    hazard = quake || entity_type.match?(/hazard|occurrence/) ||
      types.any? { |t| t.match?(/flood|wildfire|storm|eruption|hurricane|cyclone|heatwave|landslide/) }
    maritime = entity_type == "corridor" || names.match?(/strait|canal|gulf|red sea|port|shipping|tanker|vessel|maritime/) ||
      types.any? { |t| t.match?(/maritime|vessel|ship|piracy/) }
    unrest = types.any? { |t| t.match?(/protest|unrest|riot|demonstration|strike_action/) }

    if conflict
      picks["fires"] = "Thermal anomalies can corroborate reported strikes"
      picks["conflict_events"] = "Recorded conflict events give the pattern this fits"
      picks["aircraft"] = "Airspace activity and gaps are telling around active conflict"
      picks["military_bases"] = "Installations near the anchor frame the reports"
      picks["notams"] = "Airspace closures often confirm what reports claim"
    end
    if maritime
      picks["ships"] = "The story is about traffic through this water"
      picks["infrastructure"] = "Cables and pipelines through the corridor are the exposure"
      picks["aircraft"] ||= "Patrol and reconnaissance activity shows over chokepoints"
    end
    if quake
      picks["earthquakes"] = "The instrument record of the event itself"
    end
    if hazard
      picks["weather_alerts"] = "Active alerts for the same area"
      picks["fires"] ||= "Hotspots track wildfire and damage" unless quake
    end
    if unrest || hazard
      picks["webcams"] = "Someone may be pointing a camera at this right now"
    end

    picks.select { |key, _| available_keys.include?(key) }
  end

  # Minimal chat client, following the Net::HTTP shape the other resolvers use.
  class OpenAiChat
    def call(system:, user:)
      uri = URI(ENDPOINT)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT

      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{ENV['OPENAI_API_KEY']}"
      request["Content-Type"] = "application/json"
      request.body = {
        model: MODEL,
        temperature: 0,
        response_format: { type: "json_object" },
        messages: [
          { role: "system", content: system },
          { role: "user", content: user }
        ]
      }.to_json

      response = http.request(request)
      raise "OpenAI #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body).dig("choices", 0, "message", "content")
    end
  end
end
