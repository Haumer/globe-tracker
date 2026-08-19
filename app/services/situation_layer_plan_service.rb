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
  # Half-width of the box around the anchor when it has no measured extent.
  # Wide enough to catch the airfield and the port serving a city, small
  # enough that a Kyiv box does not reach Minsk.
  DEFAULT_RADIUS_KM = 150.0
  # A measured footprint can widen the box (Hormuz), but it stays bounded --
  # past this, "near this situation" has become "on this continent".
  MAX_RADIUS_KM = 600.0
  KM_PER_DEGREE_LAT = 111.32

  BOARD_CACHE_TTL = 2.minutes
  AVAILABILITY_CACHE_TTL = 5.minutes

  # meaning: is written for two readers at once -- the curator's prompt and the
  # chip tooltip -- so it says what the data is, not how it is drawn.
  # refresh_seconds: 0 means fetch once per selection; anything else is a live
  # layer the client re-polls while it is on.
  CATALOG = [
    { key: "boundaries", title: "Boundary", kind: "boundaries", baseline: true, refresh_seconds: 0,
      meaning: "the administrative boundary containing the anchor, drawn instead of a nominal circle" },
    { key: "fires", title: "Heat", kind: "fires", refresh_seconds: 300,
      meaning: "satellite thermal anomalies (NASA FIRMS) — wildfires, and possible strikes in conflict zones" },
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
    { key: "military_bases", title: "Bases", kind: "military_bases", refresh_seconds: 0,
      meaning: "known military installations" },
    { key: "infrastructure", title: "Infra", kind: "infrastructure", refresh_seconds: 0,
      meaning: "pipelines and submarine cables running through the area" },
    { key: "satellites", title: "Sat passes", kind: "satellites", refresh_seconds: 0,
      meaning: "upcoming imaging-satellite passes over the anchor" },
  ].freeze

  def self.call(situation_id:, curator: SituationLayerCurator, now: Time.current)
    situation = board(now: now)[:situations]&.find { |row| row[:id] == situation_id }
    return nil unless situation

    new(situation: situation, curator: curator, now: now).call
  end

  # The board is what /api/situations already serves; a layer plan should not
  # cost a second full build per click.
  def self.board(now: Time.current)
    Rails.cache.fetch("situation-board:v1:#{SituationBuilder::WINDOW_DAYS}", expires_in: BOARD_CACHE_TTL) do
      SituationBoardService.call(now: now)
    end
  end

  def initialize(situation:, curator: SituationLayerCurator, now: Time.current)
    @situation = situation
    @curator = curator
    @now = now
  end

  def call
    return nil unless anchor[:lat] && anchor[:lng]

    curation = curate

    {
      situation_id: situation[:id],
      generated_at: now.iso8601,
      anchor: { lat: anchor[:lat], lng: anchor[:lng] },
      radius_km: radius_km,
      bbox: bbox,
      curated_by: curation.basis,
      layers: CATALOG.map { |layer| present(layer, curation) }
    }
  end

  private

  attr_reader :situation, :curator, :now

  def anchor
    situation[:anchor] || {}
  end

  def present(layer, curation)
    status = availability[layer[:key]]
    reason = curation.picks[layer[:key]]

    {
      key: layer[:key],
      title: layer[:title],
      kind: layer[:kind],
      meaning: layer[:meaning],
      baseline: layer[:baseline] || false,
      status: status,
      on_by_default: (layer[:baseline] || reason.present?) && status == "ready",
      reason: reason,
      refresh_seconds: layer[:refresh_seconds],
      sources: sources_for(layer[:key])
    }
  end

  def curate
    curator.call(situation: situation, available_keys: available_keys)
  end

  def available_keys
    availability.filter_map { |key, status| key if status == "ready" }
  end

  # ── geometry ─────────────────────────────────────────────────────────

  def radius_km
    measured = situation.dig(:concerns, :radius_km).to_f
    [[measured, DEFAULT_RADIUS_KM].max, MAX_RADIUS_KM].min
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
      country = situation.dig(:concerns, :country_code)
      return [] unless country

      [
        { url: "/api/regional_district_boundaries", params: { country_codes: country } },
        { url: "/api/geography/boundaries", params: { dataset: "admin1", country_codes: country } }
      ]
    when "fires"
      # The endpoint serves the recent global set; the client clips to the box.
      [{ url: "/api/fire_hotspots", params: {} }]
    when "aircraft"
      [{ url: "/api/flights", params: aviation_bbox }]
    when "ships"
      [{ url: "/api/ships", params: aviation_bbox }]
    when "webcams"
      [{ url: "/api/webcams", params: compass_bbox.merge(limit: 40) }]
    when "conflict_events"
      [{ url: "/api/conflict_events", params: aviation_bbox }]
    when "earthquakes"
      [{ url: "/api/earthquakes", params: { from: (now - 7.days).iso8601, to: now.iso8601 } }]
    when "weather_alerts"
      [{ url: "/api/weather_alerts", params: aviation_bbox }]
    when "notams"
      [{ url: "/api/notams", params: aviation_bbox }]
    when "military_bases"
      [{ url: "/api/military_bases", params: compass_bbox }]
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

  # ── availability ─────────────────────────────────────────────────────

  # "ready" means a fetch now would draw something real; "unconfigured" means
  # the source needs a key the deployment does not have; "empty" means the
  # source is wired but has nothing yet. The client shows all three honestly
  # rather than a chip that toggles nothing.
  def availability
    @availability ||= begin
      # The probes are deployment-wide facts and cacheable; the boundary status
      # depends on this situation's anchor country and must never be shared.
      shared = Rails.cache.fetch("situation-layers:availability:v1", expires_in: AVAILABILITY_CACHE_TTL) do
        probe_availability
      end
      shared.merge("boundaries" => situation.dig(:concerns, :country_code).present? ? "ready" : "empty")
    end
  end

  def probe_availability
    {
      "fires" => probe(FireHotspot.recent, key: ENV["FIRMS_MAP_KEY"]),
      "aircraft" => Flight.where("updated_at > ?", 10.minutes.ago).exists? ? "ready" : "empty",
      "ships" => probe(Ship.where("updated_at > ?", 6.hours.ago), key: ENV["AISSTREAM_API_KEY"]),
      "webcams" => webcams_status,
      "conflict_events" => ConflictEvent.exists? ? "ready" : "empty",
      "earthquakes" => Earthquake.exists? ? "ready" : "empty",
      "weather_alerts" => WeatherAlert.active.exists? ? "ready" : "empty",
      # The NOTAM layer always has its static global no-fly zones.
      "notams" => "ready",
      "military_bases" => MilitaryBase.exists? ? "ready" : "empty",
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
