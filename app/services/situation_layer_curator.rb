# The per-situation judgement call, made once and cached: everything about one
# situation's globe view that is a matter of reading the story rather than of
# geometry or data plumbing.
#
# One model call answers five questions together, because they are the same
# read of the same evidence:
#
#   brief     -- two or three sentences of prose the panel leads with
#   radius_km -- how far "relevant context" extends. A city protest is a 40 km
#                story; strikes across a strait reach three countries. This is
#                the lever that sizes the bbox every layer fetches with, so it
#                is also the clutter control.
#   picks     -- which optional overlays inform this story (the original job)
#   regions   -- first-level admin regions materially affected, graded
#                high/moderate, so the boundary layer can shade nuance instead
#                of one containing polygon
#   related   -- other current situations that are plausibly the same story
#                (a retaliation pair, one campaign in two theaters)
#
# Two bases, reported so the client can say which one it is showing:
#
#   "ai"        -- the model read the situation. Closed catalog, unknown keys
#                  dropped, values clamped, a failure never raises.
#   "heuristic" -- no model available (or it failed); rules keyed on the event
#                  types and the anchor entity pick layers, and the judgement
#                  fields stay empty rather than being faked.
#
# Caching is the point, not an optimization: the result is computed in the
# background (WarmSituationLayersJob) as soon as a situation is built or
# changes, so selecting one on the globe reads a warm cache instead of paying
# a live model call. The cache key is a fingerprint of what the model actually
# read -- membership and report volume -- so a new cluster joining, or the
# report count doubling, is exactly the "new info requires a rethink" trigger;
# one more article on an existing cluster is not.
class SituationLayerCurator
  MODEL = ENV.fetch("LAYER_CURATOR_MODEL", "gpt-4.1-mini").freeze
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze
  OPEN_TIMEOUT = 10
  READ_TIMEOUT = 30
  MAX_PICKS = 6
  MAX_REGIONS = 6
  MAX_RELATED = 3
  MIN_RADIUS_KM = 25
  MAX_RADIUS_KM = 1200
  CACHE_TTL = 24.hours

  Result = Struct.new(:basis, :picks, :brief, :radius_km, :regions, :related, keyword_init: true)

  def self.call(situation:, available_keys:, neighbors: [], client: nil)
    new(situation: situation, available_keys: available_keys, neighbors: neighbors, client: client).call
  end

  def initialize(situation:, available_keys:, neighbors: [], client: nil)
    @situation = situation
    @available_keys = available_keys
    @neighbors = neighbors
    @client = client
  end

  def call
    Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
      ai_result || heuristic_result
    end
  end

  private

  attr_reader :situation, :available_keys, :neighbors

  # The rethink trigger. Membership changing (a cluster joins or leaves) or the
  # report volume doubling are new information worth a fresh read; one more
  # article trickling into an existing cluster is not, and keying on
  # last_seen_at (as v1 did) busted the cache on every trickle -- which is why
  # selection used to pay a live model call.
  def cache_key
    cluster_ids = situation[:members].to_a.filter_map { |m| m[:cluster_id] }.sort.join(",")
    volume_bucket = Math.log2([situation[:article_count].to_i, 1].max).floor

    fingerprint = [
      situation[:id],
      Digest::MD5.hexdigest(cluster_ids),
      volume_bucket,
      available_keys.sort.join(",")
    ].join(":")
    # v3: prompt learned that picks need a concrete mechanism and routine
    # stories need none -- cached v2 judgements predate that discipline.
    "situation-layer-curation:v3:#{fingerprint}"
  end

  # ── model path ───────────────────────────────────────────────────────

  def ai_result
    client = @client || default_client
    return nil unless client

    content = client.call(system: system_prompt, user: user_prompt)
    parsed = parse_response(content)
    return nil if parsed.nil?

    parsed
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
      You are the analyst setting up the globe view for one news situation.
      Respond with JSON only, in this shape:
      {"brief": "...", "radius_km": <number>,
       "layers": [{"key": "...", "reason": "..."}],
       "regions": [{"name": "...", "country_code": "..", "impact": "high"}],
       "related": [{"id": <id from the nearby list>, "reason": "..."}]}

      brief: two or three plain sentences an analyst would want first -- what
      is happening, where it stands, what to watch. No hedging boilerplate.

      radius_km: how far relevant context extends from the anchor. This sizes
      the box every data overlay is fetched with, so it is also the clutter
      control: hyper-local unrest in one city is 30-80 km; one metropolitan
      area and its surroundings 100-200; a war fought across one country
      300-600; a regional exchange of strikes spanning several countries
      500-1200. Read the headlines: if the events they report span multiple
      countries, the radius must reach them. Pick the number this story
      needs, between #{MIN_RADIUS_KM} and #{MAX_RADIUS_KM}.

      layers: overlays that would genuinely inform this specific story,
      ordered by how much each informs -- only the strongest two or three
      will be drawn, the rest are offered as suggestions. A pick needs a
      concrete mechanism in THIS story: ships because the story is about
      vessels or a waterway, aircraft because an actual flight or airspace
      matters, heat because something is burning or being struck. Never pick
      a layer because it is generically nearby -- ships for a landlocked
      city, airspace for a story with no aviation angle. A routine story
      (sports, entertainment, culture, ordinary politics) usually needs
      none: return [] and a small radius rather than inventing relevance.
      Fewer is better; never more than #{MAX_PICKS}; use only keys from the
      list given. Each reason is one short sentence tied to this situation.

      regions: the first-level administrative regions (provinces, states,
      governorates) materially affected, graded "high" or "moderate" impact,
      with the ISO 3166-1 alpha-2 country code. An earthquake shakes several
      provinces unevenly; strikes land in specific ones. Name only regions
      you are confident about, at most #{MAX_REGIONS}. [] if none.

      related: ids from the nearby-situations list that are plausibly part of
      the same story -- a retaliation pair, one campaign seen from two
      theaters, the same place tracked under two names, a shared cause. The
      board often splits one story; connecting the pieces is valuable, so
      name every genuine connection you see. At most #{MAX_RELATED}, only
      from the list given. [] if none.
    PROMPT
  end

  def user_prompt
    types = situation[:members].to_a.filter_map { |m| m[:event_type] }.tally
      .sort_by { |_, count| -count }.first(6).map { |type, count| "#{type} x#{count}" }
    headlines = situation[:members].to_a.filter_map { |m| m[:headline] }.first(8)

    neighbor_lines = neighbors.map do |n|
      "- id #{n[:id]}: #{n[:name]} (#{n[:distance_km].round} km away#{n[:country] ? ", #{n[:country]}" : ""})"
    end

    <<~PROMPT
      Situation: #{situation[:name]}
      Anchored on: #{situation.dig(:concerns, :entity_type) || "actor (no place of its own)"}
      Country: #{situation.dig(:concerns, :country_code) || "unknown"}
      Anchor: #{situation.dig(:anchor, :lat)&.round(2)}, #{situation.dig(:anchor, :lng)&.round(2)}
      Measured extent: #{situation.dig(:concerns, :radius_km) ? "#{situation.dig(:concerns, :radius_km)} km" : "none"}
      Event types: #{types.join(", ").presence || "unknown"}
      Sample headlines:
      #{headlines.map { |h| "- #{h}" }.join("\n")}

      Available overlays:
      #{catalog_lines.join("\n")}

      Nearby situations:
      #{neighbor_lines.join("\n").presence || "(none)"}
    PROMPT
  end

  def catalog_lines
    SituationLayerPlanService::CATALOG.filter_map do |layer|
      next if layer[:baseline]
      next unless available_keys.include?(layer[:key])

      "- #{layer[:key]}: #{layer[:meaning]}"
    end
  end

  def parse_response(content)
    return nil if content.blank?

    json = content[/\{.*\}/m]
    return nil unless json

    data = JSON.parse(json)
    picks = parse_picks(data["layers"])
    return nil if picks.nil?

    Result.new(
      basis: "ai",
      picks: picks,
      brief: data["brief"].to_s.strip.presence,
      radius_km: parse_radius(data["radius_km"]),
      regions: parse_regions(data["regions"]),
      related: parse_related(data["related"])
    )
  rescue JSON::ParserError
    nil
  end

  def parse_picks(rows)
    return nil unless rows.is_a?(Array)

    rows.first(MAX_PICKS).each_with_object({}) do |row, picks|
      key = row["key"].to_s
      next unless available_keys.include?(key)

      picks[key] = row["reason"].to_s.presence || "picked by the curator"
    end
  end

  def parse_radius(value)
    radius = value.to_f
    return nil unless radius.positive?

    radius.clamp(MIN_RADIUS_KM, MAX_RADIUS_KM)
  end

  def parse_regions(rows)
    Array(rows).first(MAX_REGIONS).filter_map do |row|
      next unless row.is_a?(Hash)

      name = row["name"].to_s.strip
      impact = row["impact"].to_s
      next if name.blank?
      next unless %w[high moderate].include?(impact)

      code = row["country_code"].to_s.strip.upcase
      { name: name, country_code: code.match?(/\A[A-Z]{2}\z/) ? code : nil, impact: impact }
    end
  end

  def parse_related(rows)
    valid_ids = neighbors.map { |n| n[:id] }

    Array(rows).first(MAX_RELATED).filter_map do |row|
      next unless row.is_a?(Hash)

      id = row["id"].to_i
      next unless valid_ids.include?(id)

      { id: id, reason: row["reason"].to_s.presence || "part of the same story" }
    end
  end

  # ── rules path ───────────────────────────────────────────────────────

  # No model, no fabricated judgement: layers come from rules, the scope stays
  # geometric (the plan service falls back to the measured extent), and the
  # prose/region/relation fields stay empty rather than pretending.
  def heuristic_result
    Result.new(
      basis: "heuristic",
      picks: heuristic_picks.first(MAX_PICKS).to_h,
      brief: nil,
      radius_km: nil,
      regions: [],
      related: []
    )
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
