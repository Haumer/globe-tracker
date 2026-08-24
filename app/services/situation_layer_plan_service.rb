# Which of the app's data layers belong on one situation's globe, and where to
# fetch each of them.
#
# The app already ingests far more than news -- live ADS-B flights, AIS ships,
# FIRMS thermal hotspots, webcams (Windy + YouTube), satellites with TLEs, UCDP
# conflict events, USGS earthquakes, weather alerts, NOTAMs, military bases and
# static infrastructure -- all behind existing bbox-parameterized API
# endpoints. This service fetches none of it. Per situation it answers: which
# layers are worth drawing here (SituationLayerCurator), whether each one
# actually has data or a configured source right now, and the exact URL +
# params the client should hit -- so the client never learns the three bbox
# dialects those endpoints speak.
#
# The plan carries defaults, never permissions: baseline layers always render,
# curated layers start on, and the user's toggle wins over both.
class SituationLayerPlanService
  # Half-width of the box around the anchor when neither the curator nor a
  # measured extent says otherwise. Wide enough to catch the airfield and the
  # port serving a city, small enough that a Kyiv box does not reach Minsk.
  DEFAULT_RADIUS_KM = 150.0
  # Fallback cap when the radius is geometric (measured footprint, no curator
  # judgement) -- past this, "near this situation" has become "on this
  # continent". The curator may judge wider (a regional exchange of strikes),
  # bounded by its own MAX_RADIUS_KM.
  MAX_RADIUS_KM = 600.0
  KM_PER_DEGREE_LAT = 111.32

  # How many other situations the curator gets to consider as possibly part of
  # the same story, and how far away one can be and still plausibly qualify.
  NEIGHBOR_LIMIT = 8
  NEIGHBOR_MAX_KM = 3000.0

  AVAILABILITY_CACHE_TTL = 5.minutes

  # UCDP is a historical dataset released annually — a tight window can trail
  # the latest release and blank the layer. Two years always contains one full
  # release; the client renders age, so old events cannot pass as current.
  CONFLICT_WINDOW = 2.years

  # meaning: is written for two readers at once -- the curator's prompt and the
  # chip tooltip -- so it says what the data is, not how it is drawn.
  # refresh_seconds: 0 means fetch once per selection; anything else is a live
  # layer the client re-polls while it is on.
  CATALOG = [
    { key: "boundaries", title: "Boundary", kind: "boundaries", baseline: true, refresh_seconds: 0,
      meaning: "the administrative boundary containing the anchor, drawn instead of a nominal circle" },
    { key: "aircraft", title: "Aircraft", kind: "aircraft", refresh_seconds: 12,
      meaning: "live aircraft positions from ADS-B, military traffic flagged" },
    { key: "ships", title: "Ships", kind: "ships", refresh_seconds: 60,
      meaning: "live ship positions from AIS" },
    { key: "webcams", title: "Cameras", kind: "webcams", refresh_seconds: 0,
      meaning: "nearby webcams and live YouTube streams that may show the area" },
    { key: "conflict_events", title: "Conflict", kind: "conflict_events", refresh_seconds: 0,
      meaning: "recorded conflict events (UCDP) near the anchor, with fatality estimates" },
    { key: "earthquakes", title: "Quakes", kind: "earthquakes", refresh_seconds: 300,
      meaning: "recent instrument-recorded earthquakes (USGS)" },
    { key: "weather_alerts", title: "Weather", kind: "weather_alerts", refresh_seconds: 0,
      meaning: "active severe-weather alerts for the area" },
    { key: "notams", title: "Airspace", kind: "notams", refresh_seconds: 0,
      meaning: "airspace restrictions and no-fly zones" },
    { key: "infrastructure", title: "Infra", kind: "infrastructure", refresh_seconds: 0,
      meaning: "pipelines and submarine cables running through the area" },
    { key: "satellites", title: "Sat passes", kind: "satellites", refresh_seconds: 0,
      meaning: "upcoming imaging-satellite passes over the anchor" },
  ].freeze

  def self.call(situation_id:, curator: SituationLayerCurator, now: Time.current)
    rows = board(now: now)[:situations] || []
    situation = rows.find { |row| row[:id] == situation_id }
    return nil unless situation

    new(situation: situation, siblings: rows, curator: curator, now: now).call
  end

  # The board is what /api/situations already serves; a layer plan should not
  # cost a second full build per click.
  def self.board(now: Time.current)
    SituationBoardService.cached(now: now)
  end

  def initialize(situation:, siblings: [], curator: SituationLayerCurator, now: Time.current)
    @situation = situation
    @siblings = siblings
    @curator = curator
    @now = now
  end

  def call
    return nil unless anchor[:lat] && anchor[:lng]

    {
      situation_id: situation[:id],
      generated_at: now.iso8601,
      anchor: { lat: anchor[:lat], lng: anchor[:lng] },
      radius_km: radius_km,
      bbox: bbox,
      curated_by: curation.basis,
      brief: curation.brief,
      composition: curation.composition,
      regions: curation.regions,
      related: related_rows,
      layers: CATALOG.map { |layer| present(layer, curation) }
    }
  end

  private

  attr_reader :situation, :siblings, :curator, :now

  def anchor
    situation[:anchor] || {}
  end

  def present(layer, curation)
    # The boundary layer can outgrow the anchor's own country once the curator
    # names affected regions across a border (Hormuz strikes land in Iran and
    # the UAE), so its readiness is judged here -- after curation -- rather
    # than in the shared probe.
    status = layer[:key] == "boundaries" ? boundary_status : availability[layer[:key]]
    reason = curation.picks[layer[:key]]

    {
      key: layer[:key],
      title: layer[:title],
      kind: layer[:kind],
      meaning: layer[:meaning],
      baseline: layer[:baseline] || false,
      status: status,
      # Curated picks used to auto-enable (capped at three), which
      # drew pipelines and no-fly polygons nobody asked for over every
      # selection. Picks are suggestions now -- the chip glows, the reason
      # explains, one click applies -- and only the baseline boundary starts
      # on.
      on_by_default: layer[:baseline] && status == "ready",
      # A pick beyond the on-limit keeps its reason: the chip renders as
      # suggested rather than on, and the tooltip still says why.
      reason: reason,
      refresh_seconds: layer[:refresh_seconds],
      sources: sources_for(layer[:key])
    }
  end

  def curation
    @curation ||= curator.call(situation: situation, available_keys: available_keys, neighbors: neighbors)
  end

  def available_keys
    availability.filter_map { |key, status| key if status == "ready" }
  end

  # Other current situations close enough to plausibly be the same story,
  # nearest first, handed to the curator so "related" can only ever name a
  # situation that actually exists on the board.
  def neighbors
    @neighbors ||= siblings
      .reject { |row| row[:id] == situation[:id] }
      .filter_map do |row|
        lat = row.dig(:anchor, :lat)
        lng = row.dig(:anchor, :lng)
        next unless lat && lng

        distance = haversine_km(anchor[:lat].to_f, anchor[:lng].to_f, lat.to_f, lng.to_f)
        next if distance > NEIGHBOR_MAX_KM

        { id: row[:id], name: row[:name], distance_km: distance,
          country: row.dig(:concerns, :country_code), anchor: { lat: lat, lng: lng } }
      end
      .sort_by { |row| row[:distance_km] }
      .first(NEIGHBOR_LIMIT)
  end

  def related_rows
    curation.related.to_a.filter_map do |rel|
      neighbor = neighbors.find { |n| n[:id] == rel[:id] }
      next unless neighbor

      { id: neighbor[:id], name: neighbor[:name], reason: rel[:reason],
        distance_km: neighbor[:distance_km].round, anchor: neighbor[:anchor] }
    end
  end

  # ── geometry ─────────────────────────────────────────────────────────

  # The curator's judgement wins: scope is a property of the story (a city
  # protest vs a regional exchange of strikes), not of the anchor's geometry.
  # Without one, geometry decides as before.
  def radius_km
    @radius_km ||= curation.radius_km ||
      [[situation.dig(:concerns, :radius_km).to_f, DEFAULT_RADIUS_KM].max, MAX_RADIUS_KM].min
  end

  def haversine_km(lat1, lng1, lat2, lng2)
    rad = Math::PI / 180
    dlat = (lat2 - lat1) * rad
    dlng = (lng2 - lng1) * rad
    h = Math.sin(dlat / 2)**2 +
      Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * Math.sin(dlng / 2)**2
    6371 * 2 * Math.asin(Math.sqrt([h, 1.0].min))
  end

  def bbox
    @bbox ||= begin
      lat = anchor[:lat].to_f
      lng = anchor[:lng].to_f
      dlat = radius_km / KM_PER_DEGREE_LAT
      # Longitude degrees shrink toward the poles; the cosine is floored so a
      # polar anchor degrades to a wide box instead of dividing by zero.
      dlng = radius_km / (KM_PER_DEGREE_LAT * [Math.cos(lat * Math::PI / 180).abs, 0.1].max)

      {
        north: [lat + dlat, 90.0].min.round(4),
        south: [lat - dlat, -90.0].max.round(4),
        east: [lng + dlng, 180.0].min.round(4),
        west: [lng - dlng, -180.0].max.round(4)
      }
    end
  end

  def aviation_bbox
    { lamin: bbox[:south], lamax: bbox[:north], lomin: bbox[:west], lomax: bbox[:east] }
  end

  def compass_bbox
    bbox.slice(:north, :south, :east, :west)
  end

  # ── per-layer fetch instructions ─────────────────────────────────────

  def sources_for(key)
    case key
    when "boundaries"
      codes = boundary_country_codes
      return [] if codes.empty?

      country_codes = codes.join(",")
      [
        { url: "/api/regional_district_boundaries", params: { country_codes: country_codes } },
        { url: "/api/geography/boundaries", params: { dataset: "admin1", country_codes: country_codes } }
      ]
    when "aircraft"
      [{ url: "/api/flights", params: aviation_bbox }]
    when "ships"
      [{ url: "/api/ships", params: aviation_bbox }]
    when "webcams"
      [{ url: "/api/webcams", params: compass_bbox.merge(limit: 40) }]
    when "conflict_events"
      [{ url: "/api/conflict_events",
         params: aviation_bbox.merge(from: (now - CONFLICT_WINDOW).iso8601, to: now.iso8601) }]
    when "earthquakes"
      [{ url: "/api/earthquakes", params: { from: (now - 7.days).iso8601, to: now.iso8601 } }]
    when "weather_alerts"
      [{ url: "/api/weather_alerts", params: aviation_bbox }]
    when "notams"
      [{ url: "/api/notams", params: aviation_bbox }]
    when "infrastructure"
      [
        { url: "/api/pipelines", params: {} },
        { url: "/api/submarine_cables", params: {} }
      ]
    when "satellites"
      [{ url: "/api/satellites", params: { observing: 1 } }]
    else
      []
    end
  end

  # The anchor's own country plus any country the curator's affected regions
  # reach into -- an earthquake or a cross-border exchange is not confined to
  # the country the anchor happens to sit in.
  # Most registry entities never got a country_code, so the anchor coordinate
  # itself is the fallback: whichever admin-1 region contains it names the
  # country. Without this, a situation whose curator returned no regions had
  # no boundary sources at all.
  def boundary_country_codes
    ([situation.dig(:concerns, :country_code) || anchor_country_code] +
      curation.regions.to_a.filter_map { |region| region[:country_code] })
      .compact.uniq
  end

  def anchor_country_code
    return @anchor_country_code if defined?(@anchor_country_code)

    @anchor_country_code =
      if anchor[:lat].nil? || anchor[:lng].nil?
        nil
      else
        AnchorRegionService.country_code_for(lat: anchor[:lat], lng: anchor[:lng])
      end
  end

  def boundary_status
    boundary_country_codes.any? ? "ready" : "empty"
  end

  # ── availability ─────────────────────────────────────────────────────

  # "ready" means a fetch now would draw something real; "unconfigured" means
  # the source needs a key the deployment does not have; "empty" means the
  # source is wired but has nothing yet. The client shows all three honestly
  # rather than a chip that toggles nothing.
  def availability
    @availability ||= begin
      # The probes are deployment-wide facts and cacheable; the boundary status
      # depends on this situation's anchor country and must never be shared.
      shared = Rails.cache.fetch("situation-layers:availability:v2", expires_in: AVAILABILITY_CACHE_TTL) do
        probe_availability
      end
      shared.merge("boundaries" =>
        (situation.dig(:concerns, :country_code) || anchor_country_code).present? ? "ready" : "empty")
    end
  end

  def probe_availability
    {
      "aircraft" => Flight.where("updated_at > ?", 10.minutes.ago).exists? ? "ready" : "empty",
      "ships" => probe(Ship.where("updated_at > ?", 6.hours.ago), key: ENV["AISSTREAM_API_KEY"]),
      "webcams" => webcams_status,
      "conflict_events" => ConflictEvent.in_range(Time.current - CONFLICT_WINDOW, Time.current).exists? ? "ready" : "empty",
      "earthquakes" => Earthquake.exists? ? "ready" : "empty",
      "weather_alerts" => WeatherAlert.active.exists? ? "ready" : "empty",
      # The NOTAM layer always has its static global no-fly zones.
      "notams" => "ready",
      "infrastructure" => (Pipeline.exists? || SubmarineCable.exists?) ? "ready" : "empty",
      "satellites" => Satellite.observation_capable.exists? ? "ready" : "empty"
    }
  end

  def probe(scope, key:)
    return "ready" if scope.exists?

    key.present? ? "empty" : "unconfigured"
  end

  def webcams_status
    return "ready" if Camera.alive.exists?

    (ENV["WINDY_API_KEY"].present? || ENV["YOUTUBE_API_KEY"].present?) ? "empty" : "unconfigured"
  end
end
